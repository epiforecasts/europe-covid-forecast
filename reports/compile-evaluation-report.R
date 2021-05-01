# packages ---------------------------------------------------------------------
library(purrr)
library(dplyr)
library(here)
library(readr)
library(scoringutils)
library(rmarkdown)
library(data.table)
library(covidHubUtils)
library(lubridate)

options(knitr.duplicate.label = "allow")

report_date <-
  lubridate::floor_date(lubridate::today(), "week", week_start = 7) + 1
locations <- hub_locations_ecdc

suppressWarnings(dir.create(here::here("html")))

last_forecast_date <- report_date - 7

# helper function to read in all past submissions from a model, bind them together
# to one file and copy them into the crowd forecast app folder 
# having them in one place allows to easily include other models in the 
# crowd forecast report. Could in principle also do without copying
load_and_copy_forecasts <- function(root_dir,
                                    out_file_path,
                                    new_board_name) {
  folders <- list.files(root_dir)
  files <- map(folders,
               .f = function(folder_name) {
                 files <- list.files(here(root_dir, folder_name))
                 paste(here(root_dir, folder_name, files))
               }) %>%
    unlist()
  
  forecasts <- suppressMessages(map_dfr(files, read_csv) %>%
                                  mutate(board_name = new_board_name,
                                         submission_date = forecast_date,
                                         horizon = as.numeric(gsub("([0-9]+).*$", "\\1", target))) %>%
                                  filter(grepl("inc", target),
                                         type == "quantile"))
  forecasts <- left_join(forecasts, locations) %>%
    select(-population)
  fwrite(forecasts, out_file_path)
}

# read in the EpiExpert ensemble forecast and EpiNow2 models
load_and_copy_forecasts(
  root_dir = here("submissions", "crowd-direct-forecasts"), 
  out_file_path = here("crowd-direct-forecast", "processed-forecast-data",
                       "all-epiexpert-forecasts.csv"), 
  new_board_name = "EpiExpert-ensemble"
)

# also read all EpiNow2 forecasts, give them a board_name 
load_and_copy_forecasts(
  root_dir = here("submissions", "rt-forecasts"), 
  out_file_path = here("crowd-direct-forecast", "processed-forecast-data", 
                       "all-epinow2-forecasts.csv"), 
  new_board_name = "EpiNow2"
)




## load forecasts --------------------------------------------------------------
root_dirs <- c(here::here("crowd-direct-forecast", "processed-forecast-data"), 
               here::here("crowd-rt-forecast", "processed-forecast-data"))
file_paths_forecast <- c(here::here(root_dirs[1], list.files(root_dirs[1])), 
                         here::here(root_dirs[2], list.files(root_dirs[2])))

prediction_data <- purrr::map_dfr(file_paths_forecast, 
                                  .f = function(x) {
                                    data <- data.table::fread(x) 
                                    
                                    data[, target_end_date := as.Date(target_end_date)]
                                    data[, forecast_date := calc_submission_due_date(forecast_date)]
                                    data[, submission_date := as.Date(submission_date)]
                                    if (grepl("-rt", x)) {
                                      data[, board_name := paste(model, "(Rt)")]
                                      data[, model := NULL]
                                    }
                                    return(data)
                                  }) %>%
  dplyr::mutate(target_type = ifelse(grepl("death", target), "death", "case")) %>%
  dplyr::rename(prediction = value, 
                model = board_name) %>%
  dplyr::mutate(horizon = as.numeric(substring(target, 1, 1))) %>%
  dplyr::filter(type == "quantile") %>%
  dplyr::select(location, forecast_date, quantile, prediction, 
                horizon, model, target_end_date, target, target_type) %>%
  dplyr::left_join(locations)

files <- list.files(here::here("data-raw"))
file_paths <- here::here("data-raw", files[grepl("weekly-incident", files)])
names(file_paths) <- c("case", "death")

truth <- purrr::map_dfr(file_paths, readr::read_csv, .id = "target_type") %>%
  dplyr::rename(true_value = value) %>%
  dplyr::mutate(target_end_date = as.Date(target_end_date)) %>%
  dplyr::arrange(location, target_type, target_end_date) %>%
  dplyr::left_join(locations)

data <- scoringutils::merge_pred_and_obs(prediction_data, truth, 
                                         join = "full") %>%
  unique()

# rename target type to target variable to conform to hub format
setnames(data, old = c("target_type"), new = c("target_variable"))
data[, target_variable := ifelse(target_variable == "case", "inc case", "inc death")]

for (i in 1:nrow(hub_locations_ecdc)) {
  country_code <- hub_locations_ecdc$location[i]
  country <- hub_locations_ecdc$location_name[i]
  
  rmarkdown::render(here::here("reports", "evaluation",
                               "evaluation-by-country.Rmd"),
                    output_format = "html_document",
                    params = list(data = data,
                                  location_code = country_code,
                                  location_name = country,
                                  report_date = report_date),
                    output_file =
                      here::here("docs", "reports",
                                 paste0("evaluation-report-", report_date,
                                        "-", country, ".html")),
                    envir = new.env())
}

rmarkdown::render(here::here("reports", "evaluation",
                             "evaluation-report.Rmd"),
                  params = list(data = data,
                                report_date = report_date),
                  output_format = "html_document",
                  output_file =
                    here::here("docs", "reports", 
                               paste0("evaluation-report-", report_date,
                                      "-Overall.html")),
                  envir = new.env())

## to make this generalisable
# allow bits to be turned off and on
# somehow pass down the filtering
