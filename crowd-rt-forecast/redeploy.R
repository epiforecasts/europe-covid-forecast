library(covid.ecdc.forecasts)
library(data.table)
library(dplyr)
library(rsconnect)
library(here)

# if today is not Monday (or if it is later than 9pm on the server), 
# set submission date to the next Monday
nextweek <- weekdays(Sys.Date()) != "Monday" | 
    Sys.time() > as.POSIXct("21:00",format="%H:%M")
if (nextweek) {
  submission_date <- latest_weekday() 
} else {
  submission_date <- Sys.Date()
}

check_dir(here("crowd-rt-forecast", "data-raw"))
saveRDS(submission_date,
        here("crowd-rt-forecast", "data-raw", "submission_date.rds"))
first_forecast_date <- as.character(as.Date(submission_date) - 16)

# copy Rt data into app
if (nextweek) {
  obs_file <- here("rt-forecast", "data", "summary", "cases", submission_date, "rt.csv")
} else {
  obs_file <- here("rt-forecast", "data", "summary", "cases", submission_date, "rt.csv")
}
obs <-
  fread(obs_file) %>%
  rename(value = median, target_end_date = date) %>%
  mutate(target_type = "case", target_end_date = as.Date(target_end_date)) %>%
  filter(target_end_date <= (as.Date(first_forecast_date) + 7 * 6)) %>%
  arrange(region, target_type, target_end_date) %>%
  rename(location_name = region) %>%
  select(-strat, -type, -mean, -sd)

fwrite(obs, here("crowd-rt-forecast", "data-raw", "observations.csv"))

# copy Rt samples and fit data as well -----------------------------------------
copyrt <- function(origin_dir, target_dir, locations, date) {
  for (location in locations) {
    origin_folder <- here(origin_dir, location, date)
    target_folder <- here(target_dir, location)
    
    if (dir.exists(origin_folder)) {
      check_dir(target_folder)
      file.copy(from = origin_folder, to = target_folder, recursive = TRUE)
      
      # read in epinow2 fit and thin
      fit <- readRDS(here(target_folder, date, "model_fit.rds")) %>%
        shredder::stan_slice(seq(1, 450, by = 450/25), inc_warmup = FALSE)
      saveRDS(fit, here(target_folder, date, "model_fit.rds"))
      
      # reconstruct the estimate_samples.rds file
      min_date <- readRDS(here(target_folder, date, "summarised_estimates.rds"))$date %>%
        min(na.rm = TRUE)
      df <- rstan::extract(fit, pars = "R")[[1]] %>%
        t() %>%
        as.data.table() 
      colnames(df) <- as.character(1:ncol(df))
      df <- df[, date := as.Date(min(min_date)) + 0:(nrow(df) - 1)] %>%
        melt(id.vars = "date")
      setnames(df, old = c("variable"), new = c("sample"))
      df <- df[!is.na(value)]
      df[, sample := as.numeric(sample)]
      
      saveRDS(df, here(target_folder, date, "estimate_samples.rds"))
    }
  }
}
origin_dir <- here("rt-forecast", "data", "samples", "cases")
target_dir <- here("crowd-rt-forecast", "data-raw", "samples", "cases")
locations <- list.files(origin_dir)
if (nextweek) {
 copyrt(origin_dir, target_dir, locations, submission_date)
} else {
 copyrt(origin_dir, target_dir, locations, submission_date)
}

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
