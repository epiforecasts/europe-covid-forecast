# Packages ----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(data.table)
library(dplyr)
library(here)
library(lubridate)
library(gh)
library(tibble)
library(purrr)

owner <- "covid19-forecast-hub-europe"
repo <- "covid19-forecast-hub-europe"
snapshots_path <- "data-truth/OWID/truth"
local_path <- here::here("data-raw/OWID/")
if (!dir.exists(local_path)) dir.create(local_path)

## get snapshots
query <- "/repos/{owner}/{repo}/contents/{path}"

files <-
  gh::gh(query,
         owner = owner,
         repo = repo,
         path = snapshots_path,
         .limit = Inf)
file_names <- vapply(files, `[[`, "name", FUN.VALUE = "")

fdf <- tibble(name = file_names) %>%
  mutate(date = as.Date(
    sub("^.+(20[0-9]{2}-[0-9]{2}-[0-9]{2}).*$", "\\1", name)
  )) %>%
  filter(wday(date) == 2) %>%
  arrange(date) %>%
  tail(n = 12) ## use 3 months of snapshots

existing_files <- list.files(
  here::here("data-raw", "OWID"),
  pattern = "Hospitalizations"
)

dl_files <- setdiff(fdf$name, existing_files)

download_data_file <- function(file_name) {
  download.file(
    url = paste0(
      "https://raw.githubusercontent.com/covid19-forecast-hub-europe",
      "/covid19-forecast-hub-europe/main/data-truth/OWID/truth/",
      gsub(" ", "%20", file_name)
    ),
    destfile = file.path(local_path, file_name)
  )
}

res <- purrr::map(dl_files, download_data_file)

# Source raw data ---------------------------------------------------------
raw_dt <- list()
raw_dt[["hosp"]] <-
  fread("https://raw.githubusercontent.com/covid19-forecast-hub-europe/covid19-forecast-hub-europe/main/data-truth/OWID/truth_OWID-Incident%20Hospitalizations.csv")
  
# Assign location names ---------------------------------------------------
dt <- lapply(raw_dt, function(dt) {
  dt <- merge(dt[, .(date = as_date(date), location, value)], locations[, .(location, location_name)], all.x = TRUE)
  setcolorder(dt, c("location", "location_name", "date", "value"))
  dt <- as_tibble(dt)
})
# ==============================================================================

# weekly data
fwrite(dt[["hosp"]], here("data-raw", "weekly-incident-hosp.csv"))

# Forecast date ---------------------------------------------------------------
forecast_date <- ceiling_date(Sys.Date() - 1, unit = "week", week_start = 1)
fwrite(list(forecast_date), here("data-raw", "forecast-date.csv"))
