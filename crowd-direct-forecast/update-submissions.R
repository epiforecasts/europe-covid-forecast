library(covid.ecdc.forecasts)
library(googledrive)
library(googlesheets4)
library(dplyr)
library(purrr)
library(data.table)
library(lubridate)
library(here)
library(tidyr)

# Google sheets authentification -----------------------------------------------
google_auth()

spread_sheet <- "1nOy3BfHoIKCHD4dfOtJaz4QMxbuhmEvsWzsrSMx_grI"
identification_sheet <- "1GJ5BNcN1UfAlZSkYwgr1-AxgsVA2wtwQ9bRwZ64ZXRQ"

# setup ------------------------------------------------------------------------
submission_date <- latest_weekday()
median_ensemble <- TRUE
# grid of quantiles to obtain / submit from forecasts
quantile_grid <- c(0.01, 0.025, seq(0.05, 0.95, 0.05), 0.975, 0.99)

# load data from Google Sheets -------------------------------------------------
# load identification
ids <- try_and_wait(read_sheet(ss = identification_sheet, sheet = "ids"))
# load forecasts
forecasts <- try_and_wait(read_sheet(ss = spread_sheet))

# data will be deleted by the German Hub stuff that runs afterwards
delete_data <- TRUE
if (delete_data) {
  # add forecasts to backup sheet
  try_and_wait(
    sheet_append(
      ss = spread_sheet, sheet = "oldforecasts", data = forecasts
      ))
  # delete data from sheet
  cols <- data.frame(matrix(ncol = ncol(forecasts), nrow = 0))
  names(cols) <- names(forecasts)
  try_and_wait(
    write_sheet(
    data = cols, ss = spread_sheet, sheet = "predictions"
    ))
}

# obtain raw and filtered forecasts, save raw forecasts-------------------------
locations <-
  fread("https://raw.githubusercontent.com/epiforecasts/covid19-forecast-hub-europe/main/data-locations/locations_eu.csv") # nolint

raw_forecasts <- forecasts %>%
  left_join(locations, by = "location_name") %>%
  select(-population)

# use only the latest forecast from a given forecaster
filtered_forecasts <- raw_forecasts %>%
  # interesting question whether or not to include foracast_type here. 
  # if someone reconnecs and then accidentally resubmits under a different
  # condition should that be removed or not? 
  group_by(forecaster_id, location, target_type) %>%
  dplyr::filter(forecast_time == max(forecast_time)) %>%
  ungroup()

# replace forecast duration with exact data about forecast date and time
# define function to do this for raw and filtered forecasts
replace_date_and_time <- function(forecasts) {
  forecast_times <- forecasts %>%
    group_by(forecaster_id, location, target_type) %>%
    summarise(forecast_time = unique(forecast_time)) %>%
    ungroup() %>%
    arrange(forecaster_id, forecast_time) %>%
    group_by(forecaster_id) %>%
    mutate(forecast_duration = c(NA, diff(forecast_time))) %>%
    ungroup()

  forecasts <- inner_join(
    forecasts, forecast_times,
    by = c("forecaster_id", "location", "target_type", "forecast_time")) %>%
    mutate(forecast_week = epiweek(forecast_date),
           target_end_date = as.Date(target_end_date)) %>%
    select(-forecast_time)
  return(forecasts)
}

# replace time with duration and date with epiweek
raw_forecasts <- replace_date_and_time(raw_forecasts)
filtered_forecasts <- replace_date_and_time(filtered_forecasts)

check_dir(here("crowd-direct-forecast", "raw-forecast-data"))
# write raw forecasts
fwrite(raw_forecasts %>% select(-board_name),
       here("crowd-direct-forecast", "raw-forecast-data",
            paste0(submission_date, "-raw-forecasts.csv")))

# obtain quantiles from forecasts ----------------------------------------------
# define function that returns quantiles depending on condition and distribution
calculate_quantiles <- function(quantile_grid, median, width, forecast_type, 
                                distribution, lower_90, upper_90) {
  if (distribution == "log-normal") {
    values <- list(exp(qnorm(
      quantile_grid, mean = log(as.numeric(median)), sd = as.numeric(width)
      )))
  } else if (distribution == "normal") {
    values <- list((qnorm(
      quantile_grid, mean = (as.numeric(median)), sd = as.numeric(width)
      )))
  } else if (distribution == "cubic-normal") {
    values <- list((qnorm(quantile_grid,
     mean = (as.numeric(median) ^ (1 / 3)), sd = as.numeric(width))
      ) ^ 3)
  } else if (distribution == "fifth-power-normal") {
    values <- list((qnorm(quantile_grid, 
    mean = (as.numeric(median) ^ (1 / 5)), sd = as.numeric(width)
      )) ^ 5)
  } else if (distribution == "seventh-power-normal") {
    values <- list((qnorm(quantile_grid,
     mean = (as.numeric(median) ^ (1 / 7)), sd = as.numeric(width))
     ) ^ 7)
  }
  return(values)
}

forecast_quantiles <- filtered_forecasts %>%
  # disregard quantile forecasts this week
  rowwise() %>%
  mutate(quantile = list(quantile_grid),
        value = calculate_quantiles(quantile_grid, median, width, 
        forecast_type, distribution, lower_90, upper_90)) %>%
  unnest(cols = c(quantile, value)) %>%
  ungroup() %>%
  mutate(value = pmax(value, 0), # make all forecasts positive
         type = ifelse(target_type == "cases", "case", "death"), 
         target = paste0(horizon, " wk ahead inc ", type), 
         type = "quantile")

# save forecasts in quantile-format
fwrite(forecast_quantiles %>% mutate(submission_date = submission_date),
       here("crowd-direct-forecast", "processed-forecast-data",
       paste0(submission_date, "-processed-forecasts.csv")))

# omit forecasters who haven't forecasted at least two targets
forecasters_to_omit <- forecast_quantiles %>%
  select(forecaster_id, location, target_type) %>%
  unique() %>%
  group_by(forecaster_id) %>%
  mutate(n = n(), flag = n >= 2) %>%
  dplyr::filter(!flag) %>%
  pull(forecaster_id) %>%
  unique()

forecast_quantiles <- forecast_quantiles %>%
  dplyr::filter(!(forecaster_id %in% forecasters_to_omit))


# omit targets where there aren't at least two forecasts
# targets_to_keep <- forecast_quantiles %>%
#   select(forecaster_id, location, target_type) %>%
#   unique() %>%
#   group_by(location, target) %>%
#   mutate(n = n(), flag = n >= 2) %>%
#   dplyr::filter(flag) %>%
#   select(location, target_type) %>%
#   unique()
# 
# forecast_quantiles <- left_join(forecast_quantiles, 
#                                 targets_to_keep)

# make ensemble
if (median_ensemble) {
  aggregate_function <- getFunction("median")
} else {
  aggregate_function <- getFunction("mean")
}

forecast_inc <- forecast_quantiles %>%
  mutate(target_end_date = as.Date(target_end_date), 
         type = "quantile") %>%
  group_by(location, location_name, target, target_type, type,
           quantile, horizon, target_end_date) %>%
  summarise(value = aggregate_function(value)) %>%
  ungroup() %>%
  select(target, target_end_date, location, type,
         target_type, quantile, value, location_name)

# add point forecast
forecast_inc <- bind_rows(forecast_inc, 
                          forecast_inc %>%
                            dplyr::filter(quantile == 0.5) %>%
                            mutate(type = "point",
                                   quantile = NA))

forecast_submission <- forecast_inc %>%
  mutate(forecast_date = submission_date, 
         scenario_id = "forecast") %>%
  select(-target_type, -location_name) %>%
  mutate(value = round(value))

# write submission file --------------------------------------------------------
check_dir(here("submissions", "crowd-direct-forecasts", submission_date))

forecast_submission %>%
  fwrite(here("submissions", "crowd-direct-forecasts", submission_date, 
         paste0(submission_date, "-epiforecasts-EpiExpert_direct.csv")))
