# Package -----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(data.table)
library(EpiNow2)
library(here)
library(purrr)

# Dates -------------------------------------------------------------------
target_date <- get_forecast_date(dir = here("data-raw"))
target_variables <- c(cases = "case", hospitalizations = "hosp", deaths = "death")

# Locations ---------------------------------------------------------------
base_url <- "https://raw.githubusercontent.com/epiforecasts/"
locations <- fread(paste0(
  base_url,
 "covid19-forecast-hub-europe/main/data-locations/locations_eu.csv")
 )

# Get forecasts -----------------------------------------------------------
forecasts <- purrr::map(c("cases", "hospitalizations", "deaths"), \(x) { 
  suppressWarnings(res <- get_regional_results(
    results_dir = here("rt-forecast", "data", "samples", x),
    date = target_date, forecast = TRUE,
    samples = TRUE)$estimated_reported_cases$samples)
  format_forecast(res[, value := cases],
                  locations = locations,
                  forecast_date = target_date,
                  submission_date = target_date,
                  CrI_samples = 0.9,
                  frequency = "weekly",
                  target_value = target_variables[x])
}) |>
  data.table::rbindlist()

forecasts[, target_end_date := as.character(target_end_date)]

# Save forecasts ----------------------------------------------------------
rt_folder <- here("submissions", "rt-forecasts", target_date)
check_dir(rt_folder)
fwrite(forecasts,
       file.path(rt_folder, paste0(target_date, "-epiforecasts-EpiNow2.csv")))
