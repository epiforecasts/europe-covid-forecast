library(covid.ecdc.forecasts)
library(data.table)
library(dplyr)
library(rsconnect)
library(here)

# if today is not Monday, set submission date to last monday
submission_date <- latest_weekday()

check_dir(here("crowd-rt-forecast", "data-raw"))
saveRDS(submission_date,
        here("crowd-rt-forecast", "data-raw", "submission_date.rds"))
first_forecast_date <- as.character(as.Date(submission_date) - 16)

# copy Rt data into app
obs <-
  fread(
    here("rt-forecast", "data", "summary", "cases", submission_date, "rt.csv")
    ) %>%
  rename(value = median, target_end_date = date) %>%
  mutate(target_type = "case", target_end_date = as.Date(target_end_date)) %>%
  filter(target_end_date <= (as.Date(first_forecast_date) + 7 * 6)) %>%
  arrange(region, target_type, target_end_date) %>%
  rename(location_name = region) %>%
  select(-strat, -type, -mean, -sd)

fwrite(obs, here("crowd-rt-forecast", "data-raw", "observations.csv"))

# copy Rt samples and fit data as well
copyrt <- function(origin_dir, target_dir, locations, date) {
  for (location in locations) {
    origin_folder <- here(origin_dir, location, date)
    target_folder <- here(target_dir, location)
    
    if (dir.exists(origin_folder)) {
      check_dir(target_folder)
      file.copy(from = origin_folder, to = target_folder, recursive = TRUE)
    }
  }
}
origin_dir <- here("rt-forecast", "data", "samples", "cases")
target_dir <- here("crowd-rt-forecast", "data-raw", "samples", "cases")
copyrt(origin_dir, target_dir, locations, submission_date)

setAccountInfo(
  name = "cmmid-lshtm",
  token = readRDS(here(".secrets", "shiny_token.rds")),
  secret = readRDS(here(".secrets", "shiny_secret.rds"))
)

deployApp(
  appDir = here("crowd-rt-forecast"),
  appName = "crowd-rt-forecast",
  account = "cmmid-lshtm",
  forceUpdate = TRUE,
  appFiles = c("data-raw", "app.R", ".secrets")
)
