# Launch the ShinyApp (Do not remove this comment)
# RT app
library(data.table)
library(dplyr)
library(crowdforecastr)
library(magrittr)
library(rstantools)
library(lubridate)
library(shinyjs)
library(EpiNow2)
library(purrr)
library(data.table)
library(ggplot2)
library(forecasthubutils)
library(shinybusy)
library(zoo)

# devtools::install_github("epiforecasts/forecasthubutils@update-make_weekly")
# devtools::install_github("epiforecasts/crowdforecastr@rt-visualisation")
options("golem.app.prod" = TRUE)

# load submission date from data if on server
if (!dir.exists("crowd-rt-forecast")) {
  submission_date <- readRDS("data-raw/submission_date.rds")
} else {
  submission_date <- floor_date(Sys.Date(), unit = "week", week_start = 1)
  saveRDS(submission_date, "crowd-rt-forecast/data-raw/submission_date.rds")
}
first_forecast_date <- as.character(as.Date(submission_date) - 16)

# Run on local machine to load the latest data.
# Will be skipped on the shiny server
if (dir.exists("rt-forecast")) {
  obs <- fread(
    paste0("rt-forecast/data/summary/cases/", submission_date, "/rt.csv")
    ) %>%
    rename(value = median, target_end_date = date, location_name = region) %>%
    mutate(target_type = "case", target_end_date = as.Date(target_end_date)) %>%
    filter(target_end_date <= (as.Date(first_forecast_date) + 7 * 6)) %>%
    arrange(location_name, target_type, target_end_date) %>%
    select(-strat, -type, -mean, -sd)

  fwrite(obs, "crowd-rt-forecast/data-raw/observations.csv")
  
  path_to_epinow2_samples <- "crowd-rt-forecast/data-raw/samples"
} else {
  obs <- read.csv("data-raw/observations.csv")
  path_to_epinow2_samples <- "data-raw/samples"
}

run_app(
  data = obs,
  app_mode = "rt",
  selection_vars = c("location_name"),
  first_forecast_date = first_forecast_date,
  submission_date = submission_date,
  horizons = 7,
  horizon_interval = 7,
  path_service_account_json = ".secrets/crowd-forecast-app-c98ca2164f6c-service-account-token.json",
  force_increasing_uncertainty = FALSE,
  default_distribution = "normal",
  path_epinow2_samples = path_to_epinow2_samples,
  forecast_sheet_id = "1g4OBCcDGHn_li01R8xbZ4PFNKQmV-SHSXFlv2Qv79Ks",
  user_data_sheet_id = "1GJ5BNcN1UfAlZSkYwgr1-AxgsVA2wtwQ9bRwZ64ZXRQ",
  path_past_forecasts = "external_ressources/processed-forecast-data/"
)
