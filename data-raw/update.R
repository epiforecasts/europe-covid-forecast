# Packages ----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(data.table)
library(dplyr)
library(here)
library(lubridate)

# Source raw data ---------------------------------------------------------
raw_dt <- list()
raw_dt[["cases"]] <-
  fread("https://raw.githubusercontent.com/epiforecasts/covid19-forecast-hub-europe/main/data-truth/JHU/truth_JHU-Incident%20Cases.csv")
  
raw_dt[["deaths"]] <-
  fread("https://raw.githubusercontent.com/epiforecasts/covid19-forecast-hub-europe/main/data-truth/JHU/truth_JHU-Incident%20Deaths.csv")

# Assign location names ---------------------------------------------------
dt <- lapply(raw_dt, function(dt) {
  dt <- merge(dt[, .(date = as_date(date), location, value)], locations[, .(location, location_name)], all.x = TRUE)
  setcolorder(dt, c("location", "location_name", "date", "value"))
  dt <- as_tibble(dt)
})
# ==============================================================================

# Calculate weekly -------------------------------------------------------
weekly_cases <- make_weekly(dt[["cases"]])
weekly_deaths <- make_weekly(dt[["deaths"]])
  
# Save data ---------------------------------------------------------------

# daily data
fwrite(dt[["cases"]], here("data-raw", "daily-incidence-cases.csv"))
fwrite(dt[["deaths"]], here("data-raw", "daily-incidence-deaths.csv"))

# weekly data
fwrite(weekly_cases, here("data-raw", "weekly-incident-cases.csv"))
fwrite(weekly_deaths, here("data-raw", "weekly-incident-deaths.csv"))

# Forecast date ---------------------------------------------------------------
forecast_date <- ceiling_date(Sys.Date(), unit = "week", week_start = 1)
fwrite(list(forecast_date), here("data-raw", "forecast-date.csv"))
