library(covid.ecdc.forecasts)
library(here)
library(data.table)

submission_date <- latest_weekday()

folder_paths <- c(here("crowd-direct-forecast", "processed-forecast-data"), 
                here("crowd-rt-forecast", "processed-forecast-data"))

file_paths <- paste0(folder_paths, "/", submission_date, "-processed-forecasts.csv")


direct_forecasts <- data.table::fread(file_paths[1])
direct_forecasts <- direct_forecasts[, .(board_name, location,type,
                                         quantile,value,target_end_date,
                                         forecast_date = as.character(forecast_date),
                                         target)
                                     ][, scenario_id := "forecast"]

# add point forecast to direct forecasts
point <- copy(direct_forecasts)[quantile == 0.5][, `:=` (type = "point", 
                                                       quantile = NA_real_)]
direct_forecasts <- rbind(direct_forecasts, point)

rt_forecasts <- data.table::fread(file_paths[2])[, .(board_name = model, 
                                                    location,type,
                                                    quantile,value,
                                                    target_end_date,
                                                    forecast_date = as.character(forecast_date), 
                                                    target, scenario_id)]

crowd_forecasts <- rbind(direct_forecasts, rt_forecasts)
setDT(crowd_forecasts)


median_ensemble <- TRUE

if (median_ensemble) {
  aggregate_function <- getFunction("median")
} else {
  aggregate_function <- getFunction("mean")
}

# create ensemble for submission
submission <- crowd_forecasts[, .(value = aggregate_function(value)), 
                              by = c("location", "type", "quantile", 
                                     "target_end_date", "target", 
                                     "scenario_id")]
submission[, forecast_date := latest_weekday()]

# write submission file
submission_folder <- here("submissions", "crowd-forecasts", submission_date)
check_dir(submission_folder)
fwrite(submission, 
       here(submission_folder,
            paste0(submission_date, "-epiforecasts-EpiExpert.csv")))
