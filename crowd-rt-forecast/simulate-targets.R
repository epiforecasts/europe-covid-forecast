# Packages ----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(EpiNow2)
library(data.table)
library(here)
library(purrr)
library(ggplot2)
library(lubridate)
library(devtools)

# load additional functions
source_gist("https://gist.github.com/seabbs/4dad3958ca8d83daca8f02b143d152e6")

# parallel
options(mc.cores = 4)
# Set forecasting date ----------------------------------------------------
target_date <- latest_weekday()

# Get Rt forecasts --------------------------------------------------------
crowd_rt <- fread(
  here("crowd-rt-forecast", "forecast-sample-data",
       paste0(target_date, "-forecast-sample-data.csv")
))

# dropped redundant columns and get correct shape
crowd_rt <- crowd_rt[, .(location, 
                         forecaster_id,
                         board_name,
                         date = as.Date(target_end_date),
                         value = round(value, 3)
)]
crowd_rt[, sample := 1:.N, by = .(location, date)]
crowd_rt[, target := "cases"]
# temporary fix to get rid of sample numbers greater than 1000
crowd_rt[sample > 1000, sample := sample - 1000]

# Simulate cases ----------------------------------------------------------
all_forecasts <- list()

forecasters <- unique(crowd_rt$board_name)

for (forecaster in forecasters) {
  # simulate crowd cases
  dt <- copy(crowd_rt)[board_name == forecaster][
    , c("forecaster_id", "board_name") := NULL]
  simulations <- simulate_crowd_cases(
    dt,
    model_dir = here("rt-forecast", "data", "samples"),
    target_date = target_date
  )
  crowd_cases <- extract_samples(simulations, "cases")
  crowd_cases[, model := forecaster]
  
  # save output plot
  plot_dir <- here("crowd-rt-forecast", "data-raw", "plots", target_date)
  check_dir(plot_dir)
  
  walk(names(simulations), function(loc) {
    walk(names(simulations[[1]]), function(tar) {
      ggsave(paste0(loc, "-", forecaster, "-", tar, ".png"),
             simulations[[loc]][[tar]]$plot,
             path = plot_dir, height = 9, width = 9
      )
    })
  })
  
  # Simulate deaths ------------------------------------------------------------
  observations <- get_observations(dir = here("data-raw"), target_date)
  observations <- observations[region %in% unique(crowd_cases$region)]
  
  # run across all targets
  # options for estimate_secondary (EpiNow2)
  deaths_forecast <- regional_secondary(
    observations, crowd_cases[, cases := value],
    delays = delay_opts(list(
      mean = 2.5, mean_sd = 0.5,
      sd = 0.47, sd_sd = 0.2, max = 30
    )),
    return_fit = FALSE,
    secondary = secondary_opts(type = "incidence"),
    obs = obs_opts(scale = list(mean = 0.01, sd = 0.02)),
    burn_in = as.integer(max(observations$date) - min(observations$date)) - 3 * 7,
    control = list(adapt_delta = 0.98, max_treedepth = 15),
    verbose = FALSE
  )
  
  # Submission --------------------------------------------------------------
  crowd_cases <- format_forecast(crowd_cases,
                                 locations = locations,
                                 forecast_date = target_date,
                                 submission_date = target_date,
                                 target_value = "case"
  )
  
  crowd_deaths <- format_forecast(deaths_forecast$samples,
                                  locations = locations,
                                  forecast_date = target_date,
                                  submission_date = target_date,
                                  target_value = "death"
  )
  
  forecast <- rbind(crowd_cases, crowd_deaths, use.names = TRUE)
  forecast[, model := forecaster]
  
  all_forecasts[[forecaster]] <- forecast
}

all_forecasts <- rbindlist(all_forecasts)

# write to processed forecasts folder
processed_folder <- here::here("crowd-rt-forecast", "processed-forecast-data")
check_dir(processed_folder)

fwrite(all_forecasts,
       file.path(processed_folder, 
                 paste0(target_date, "-processed-forecasts.csv")))


# create ensemble
submission <- all_forecasts %>%
  dplyr::group_by(location, target, type, quantile, 
                  target_end_date, forecast_date, scenario_id) %>%
  dplyr::summarise(value = mean(value)) %>%
  dplyr::ungroup()

submission_folder <- here("submissions", "crowd-rt-forecasts", target_date)
check_dir(submission_folder)
fwrite(submission,
       file.path(submission_folder, paste0(target_date, "-epiforecasts-EpiExpert_Rt.csv")))
