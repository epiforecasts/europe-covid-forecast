# packages
library(covid.ecdc.forecasts)
library(here)
library(rsconnect)
# update data

# copy data into app
check_dir(here("crowd-forecast", "data-raw"))
file.copy(from = c(here("data-raw", "weekly-incident-cases.csv"),
            here("data-raw", "weekly-incident-deaths.csv")),
          to = here("crowd-forecast", "data-raw"),
          overwrite = TRUE)

# if today is not Monday (or if it is later than 9pm on the server), 
# set submission date to the next Monday
if (weekdays(Sys.Date()) != "Monday" | 
    Sys.time() > as.POSIXct("21:00",format="%H:%M")) {
  submission_date <- latest_weekday() + 7
} else {
  submission_date <- Sys.Date()
}

saveRDS(
  submission_date, here("crowd-forecast", "data-raw", "submission_date.rds")
  )

setAccountInfo(
  name = "cmmid-lshtm",
  token = readRDS(here(".secrets", "shiny_token.rds")),
  secret = readRDS(here(".secrets", "shiny_secret.rds"))
)

deployApp(appDir = here("crowd-forecast"),
          appName = "crowd-forecast",
          account = "cmmid-lshtm", 
          forceUpdate = TRUE,
          appFiles = c("data-raw", "app.R", ".secrets"))