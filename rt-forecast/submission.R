# Package -----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(data.table)
library(EpiNow2)
library(lubridate)
library(here)

# Dates -------------------------------------------------------------------
target_date <- get_forecast_date(dir = here("data-raw"), char = TRUE)

# Get forecasts -----------------------------------------------------------
case_forecast <- suppressWarnings(
  get_regional_results(
    results_dir = here("rt-forecast", "data", "samples", "cases"),
    date = ymd(target_date), forecast = TRUE,
    samples = TRUE)$estimated_reported_cases$samples)

death_forecast <- fread(
  here("rt-forecast", "data", "samples", "deaths",
       target_date, "samples.csv"))

# Locations ---------------------------------------------------------------
base_url <- "https://raw.githubusercontent.com/epiforecasts/"
locations <- fread(paste0(
  base_url,
 "covid19-forecast-hub-europe/main/data-locations/locations_eu.csv")
 )

# Format forecasts --------------------------------------------------------
case_forecast <- format_forecast(case_forecast[, value := cases],
                                 locations = locations,
                                 forecast_date = target_date,
                                 submission_date = target_date,
                                 CrI_samples = 0.9,
                                 target_value = "case")

death_forecast <- format_forecast(death_forecast,
                                  locations = locations,
                                  forecast_date = target_date,
                                  submission_date = target_date,
                                  target_value = "death")

death_forecast[, target_end_date := as.character(target_end_date)]
case_forecast[, target_end_date := as.character(target_end_date)]
forecast <- rbind(case_forecast, death_forecast, use.names = TRUE)

# Save forecasts ----------------------------------------------------------
rt_folder <- here("submissions", "rt-forecasts", target_date)
check_dir(rt_folder)
fwrite(forecast,
       file.path(rt_folder, paste0(target_date, "-epiforecasts-EpiNow2.csv")))