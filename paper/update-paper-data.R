library(here)
library(dplyr)
library(magrittr)
library(stringr)
library(data.table)
library(scoringutils)
library(covidHubUtils)
library(covid.ecdc.forecasts)
library(tidyr)

# ==============================================================================
# ------------------------------ update data -----------------------------------
# ==============================================================================


# ----------------------------- forecast data ----------------------------------
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# update forecast data from server ---------------------------------------------
# system(
#   paste(". data-raw/paper.sh")
# )

# ------------------------------------------------------------------------------
# load past forecasts submitted to the hub--------------------------------------

# get the correct file paths to all forecasts 
folders <- here::here("paper", list.files("paper"))
folders <- folders[
  !(grepl("\\.R", folders) | grepl(".sh", folders) | grepl(".csv", folders))
]
file_paths <- purrr::map(folders, 
                         .f = function(folder) {
                           files <- list.files(folder)
                           out <- here::here(folder, files)
                           return(out)}) %>%
  unlist()
file_paths <- file_paths[grepl(".csv", file_paths)]

# ceate a helper function to get model name from a file path
get_model_name <- function(file_path) {
  split <- str_split(file_path, pattern = "/")[[1]]
  model <- split[length(split) - 1]
  return(model)
}

# load prediction data for all submitted forecasts
prediction_data <- purrr::map_dfr(file_paths, 
                                  .f = function(file_path) {
                                    data <- data.table::fread(file_path)
                                    data[, `:=`(
                                      target_end_date = as.Date(target_end_date), 
                                      forecast_date = as.Date(forecast_date), 
                                      model = get_model_name(file_path)
                                    )]
                                    return(data)
                                  }) %>%
  dplyr::mutate(target_type = ifelse(grepl("death", target), "death", "case")) %>%
  dplyr::rename(prediction = value) %>%
  dplyr::filter(location %in% c("GB"), 
                type == "quantile", 
                grepl("inc case", target) | grepl("inc death", target)) %>%
  dplyr::mutate(location_name = "United Kingdrom") %>%
  dplyr::select(location, location_name, forecast_date, quantile, 
                prediction, model, target_end_date, target, target_type) %>%
  dplyr::mutate(horizon = as.numeric(substr(target, 1, 1)))


# ------------------------------------------------------------------------------
# load past forecasts made by participants -------------------------------------

# get file paths
root_dirs <- c(here::here("crowd-direct-forecast", "processed-forecast-data"), 
               here::here("crowd-rt-forecast", "processed-forecast-data"))
file_paths_forecast <- c(here::here(root_dirs[1], list.files(root_dirs[1])), 
                         here::here(root_dirs[2], list.files(root_dirs[2])))

# load forecasts
prediction_data_humans <- 
  purrr::map_dfr(file_paths_forecast, 
                 .f = function(x) {
                   data <- data.table::fread(x) 
                   
                   data[, target_end_date := as.Date(target_end_date)]
                   data[, forecast_date := calc_submission_due_date(forecast_date)]
                   data[, submission_date := as.character(forecast_date)]
                   if (grepl("-rt", x)) {
                     data[, board_name := paste(model, "(Rt)")]
                     data[, model := NULL]
                   }
                   return(data)
                 }) %>%
  dplyr::mutate(target_type = ifelse(grepl("death", target), 
                                     "death", "case")) %>%
  dplyr::rename(prediction = value, 
                model = board_name) %>%
  dplyr::mutate(horizon = as.numeric(substring(target, 1, 1))) %>%
  dplyr::filter(type == "quantile") %>%
  dplyr::select(location, forecast_date, quantile, prediction, expert,
                horizon, model, target_end_date, target, target_type) %>%
  dplyr::left_join(locations) %>%
  dplyr::filter(forecast_date >= "2021-05-24") %>%
  dplyr::filter(model != "EpiNow2" & model != "EpiExpert-ensemble") %>%
  dplyr::mutate(forecast_date = as.Date(forecast_date)) %>%
  dplyr::filter(location == "GB")


# fix expert status for Rt forecasts
rt_names <- prediction_data_humans %>%
  filter(is.na(expert)) %>%
  pull(model) %>% unique() %>% sort()

rt_names <- gsub(pattern = " \\(Rt\\)", replacement = "", x = rt_names)

expert_status <- prediction_data_humans %>%
  filter(model %in% rt_names) %>%
  mutate(model = paste(model, "(Rt)")) %>%
  rbind(prediction_data_humans %>% 
          filter(!is.na(expert))) %>%
  select(expert, model) %>%
  unique()

prediction_data_humans <- prediction_data_humans %>%
  select(-expert) %>%
  left_join(expert_status) 


# combine predictions ----------------------------------------------------------
predictions <- bind_rows(prediction_data, prediction_data_humans) %>%
  dplyr::select(-c(population)) %>%
  dplyr::mutate(location_name = "United Kingdom") %>%
  mutate(expert = ifelse(is.na(expert), "Unknown", 
                         ifelse(expert, "Expert", "Non-expert"))) 

usethis::use_data(predictions, overwrite = TRUE)



# -------------------------------- truth data ----------------------------------
# ------------------------------------------------------------------------------

# weekly truth data ------------------------------------------------------------
files <- list.files(here::here("data-raw"))
file_paths <- here::here("data-raw", files[grepl("weekly-incident", files)])
names(file_paths) <- c("case", "death")

truth <- purrr::map_dfr(file_paths, readr::read_csv, .id = "target_type") %>%
  dplyr::rename(true_value = value) %>%
  dplyr::mutate(target_end_date = as.Date(target_end_date)) %>%
  dplyr::arrange(location, target_type, target_end_date) %>%
  dplyr::left_join(locations) %>%
  dplyr::filter(location == "GB")

usethis::use_data(truth, overwrite = TRUE)

# daily truth data -------------------------------------------------------------
daily_cases <- fread(here("data-raw", "daily-incidence-cases.csv"))
daily_cases[, target_type := "case"]
daily_deaths <- fread(here("data-raw", "daily-incidence-deaths.csv"))
daily_deaths[, target_type := "death"]
dailytruth <- rbindlist(list(daily_cases, daily_deaths)) 
dailytruth <- dailytruth[location_name %in% c("United Kingdom")]
dailytruth_data <- dailytruth[, `:=` (location = NULL,
                                      target_end_date = as.Date(date))]
setnames(dailytruth_data, old = "value", new = "true_value")

usethis::use_data(dailytruth_data, overwrite = TRUE)



# ------------------------------ combine data ----------------------------------
# ------------------------------------------------------------------------------

forecast_dates <- as.Date("2021-05-24") + 0:12 * 7

data <- scoringutils::merge_pred_and_obs(predictions, truth, 
                                         join = "full") %>%
  unique() %>%
  dplyr::filter(is.na(forecast_date) | forecast_date %in% forecast_dates) %>%
  mutate(target_type = ifelse(target_type == "case", 
                              "Cases", "Deaths"))

log_data <- data %>%
  dplyr::mutate(true_value = log(pmax(true_value, 0) + 1),
                prediction = log(pmax(prediction, 0) + 1))

usethis::use_data(data, overwrite = TRUE)
usethis::use_data(log_data, overwrite = TRUE)


# ------------------------------ utility data ----------------------------------
# ------------------------------------------------------------------------------

models <- list()
models[["Hub-submissions"]] <- prediction_data$model %>% unique()
models[["participants"]] <- prediction_data_humans$model %>% unique()

usethis::use_data(models, overwrite = TRUE)

study_dates <- list()
study_dates[["forecast_dates"]] <- data %>%
  filter(!is.na(forecast_date)) %>%
  pull(forecast_date) %>% unique()
study_dates[["target_end_dates"]] <- data %>%
  filter(!is.na(prediction)) %>%
  pull(target_end_date) %>% unique()
study_dates[["study_dates"]] <- 
  c(min(study_dates$forecast_dates), max(study_dates$target_end_dates))
study_dates[["plot_dates"]] <- 
  c(as.Date("2021-04-01"), as.Date("2021-09-11"))

usethis::use_data(study_dates, overwrite = TRUE)