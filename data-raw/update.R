# Packages ----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(data.table)
library(dplyr)
library(here)
library(lubridate)
library(gh)
library(tibble)
library(purrr)

base_path <- here::here("data-raw")

for (source in c("OWID", "ECDC")) {
  owner <- "covid19-forecast-hub-europe"
  repo <- "covid19-forecast-hub-europe"
  snapshots_path <- file.path("data-truth", source, "truth")
  local_path <- file.path(base_path, source)
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

  fdf <- tibble::tibble(name = file_names) %>%
    dplyr::mutate(
      date = as.Date(
        sub("^.+(20[0-9]{2}-[0-9]{2}-[0-9]{2}).*$", "\\1", name)
      ),
      target = sub("^truth.* ([^ -]+)-20[0-9]{2}-.*csv$", "\\1", name)
    ) %>%
    dplyr::arrange(date) %>%
    dplyr::filter(wday(date) == 6) %>%
    dplyr::group_by(target) %>%
    dplyr::slice_tail(n = 24) %>% ## use 6 months of snapshots
    dplyr::ungroup()
  
  existing_files <- list.files(
    here::here("data-raw", source),
    pattern = "^truth.*csv$"
  )

  dl_files <- setdiff(fdf$name, existing_files)

  download_data_file <- function(file_name) {
    download.file(
      url = paste0(
        "https://raw.githubusercontent.com/covid19-forecast-hub-europe",
        "/covid19-forecast-hub-europe/main/data-truth/", source, "/truth/",
        gsub(" ", "%20", file_name)
      ),
      destfile = file.path(local_path, file_name)
    )
  }

  res <- purrr::map(dl_files, download_data_file)

  # Source raw data ---------------------------------------------------------
  latest_file_names <- fdf %>%
    dplyr::group_by(target) %>%
    dplyr::summarise(name = paste0(unique(
      sub("-20[0-9]{2}-.*\\.csv$", "", name)
    ), ".csv"), .groups = "drop")
  raw_dt <- purrr::map(latest_file_names$name, \(x) fread(paste0(
    "https://raw.githubusercontent.com/covid19-forecast-hub-europe/",
    "covid19-forecast-hub-europe/main/data-truth/", source, "/",
    gsub(" ", "%20", x)
  )))

  # Assign location names ---------------------------------------------------
  dt <- lapply(raw_dt, function(dt) {
    dt <- merge(dt[, .(date = as_date(date), location, value)], locations[, .(location, location_name)], all.x = TRUE)
    setcolorder(dt, c("location", "location_name", "date", "value"))
    return(tibble::as_tibble(dt))
  })
  names(dt) <- latest_file_names$target
  # ==============================================================================

  # weekly data
  res <- purrr::map(names(dt), \(x) fwrite(
    dt[[x]], here("data-raw", paste0("weekly-incident-", tolower(x), ".csv"))
  ))
}

cutoffs <- purrr::map(c("OWID", "ECDC"), \(x) fread(paste0(
    "https://raw.githubusercontent.com/covid19-forecast-hub-europe/", 
    "covid19-forecast-hub-europe/main/data-truth/", x, "/",
    "recommended-cutoffs.csv"
))) |>
  data.table::rbindlist(fill = TRUE)
cutoffs <- cutoffs[is.na(target_variable), target_variable := "inc hosp"]
fwrite(cutoffs, here("data-raw", "recommended-cutoffs.csv"))

 # Forecast date ---------------------------------------------------------------
forecast_date <- floor_date(today(), unit = "week", week_start = 6) + 2
fwrite(list(forecast_date), here("data-raw", "forecast-date.csv"))
