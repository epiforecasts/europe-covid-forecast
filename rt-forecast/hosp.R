# Packages -----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(EpiNow2, quietly = TRUE)
library(data.table, quietly = TRUE)
library(future, quietly = TRUE)
library(here, quietly = TRUE)
library(lubridate, quietly = TRUE)

# Set target date ---------------------------------------------------------
target_date <- get_forecast_date(dir = here("data-raw"), char = TRUE)
print(target_date)

# Update delays -----------------------------------------------------------
generation_time <- readRDS(
  here("rt-forecast", "data", "delays", "generation_time.rds")
  )
incubation_period <- readRDS(
  here("rt-forecast", "data","delays", "incubation_period.rds")
  )
onset_to_report <- readRDS(
  here("rt-forecast", "data", "delays", "onset_to_report.rds")
  )

# Get hospitalizations  ---------------------------------------------------------------
hosp <- fread(file.path("data-raw", "weekly-incident-hosp.csv"))
hosp <- hosp[, .(region = as.character(location_name),
                 date = as.Date(date), confirm = value)]
hosp <- hosp[confirm < 0, confirm := 0]
hosp <- hosp[date >= (max(date) - weeks(12))]
setorder(hosp, region, date)

snapshot_files <- list.files(here::here("data-raw", "OWID"), full.name = TRUE)
snapshot_files <- tail(snapshot_files, 12)

snapshots <- lapply(snapshot_files, fread)

cutoffs <- fread(paste0(
  "https://raw.githubusercontent.com/covid19-forecast-hub-europe/", 
  "covid19-forecast-hub-europe/main/data-truth/OWID/recommended-cutoffs.csv"
))

no_cutoff <- setdiff(hosp$region, cutoffs$location_name)
trunc_loc <- lapply(unique(cutoffs$location_name), function(loc) {
  loc_snapshots <- lapply(snapshots, function(x) {
    x <- x[location_name == loc][, list(date, confirm = value)]
    if (nrow(x) > 0) x <- x[date > max(date) - 16 * 7]
  })
  safe_estimate_truncation <- purrr::safely(estimate_truncation)
  est <- safe_estimate_truncation(loc_snapshots, trunc_max = 28, chains = 2)
  return(est$result$dist)
})
failure <- vapply(trunc_loc, is.null, FALSE)
failed_cutoff_names <- unique(cutoffs$location_name)[failure]
cutoff_names <- unique(cutoffs$location_name)[!failure]
trunc_loc <- trunc_loc[!failure]
names(trunc_loc) <- cutoff_names

trunc <- opts_list(trunc_opts(), hosp)
trunc[cutoff_names] <- lapply(trunc_loc, trunc_opts)
trunc[!failed_cutoff_names] <- NULL

loc_names <- names(trunc)
hosp <- hosp[region %in% loc_names]

# Set up parallel execution -----------------------------------------------
no_cores <- setup_future(hosp)

# Run Rt estimation -------------------------------------------------------
rt <- opts_list(
  rt_opts(prior = list(mean = 1.0, sd = 0.1), future = "estimate", rw = 7), hosp
)
# add population adjustment for each country
rt <- lapply(loc_names, function(loc, proc_pop = 1) {
  rt_loc <- rt[[loc]]
  rt_loc$pop <- locations[location_name %in% loc, ]$population
  rt_loc$pop <- as.integer(rt_loc$pop * proc_pop)
  return(rt_loc)
})
names(rt) <- loc_names

regional_epinow(
  reported_cases = hosp,
  generation_time = generation_time, 
  delays = delay_opts(incubation_period, onset_to_report),
  truncation = trunc,
  rt = rt,
  gp = NULL,
  stan = stan_opts(samples = 2000, warmup = 500,
                   chains = 2, cores = no_cores),
  obs = obs_opts(scale = list(mean = 0.05, sd = 0.025)),
  horizon = 30,
  output = c("region", "summary", "timing", "samples", "fit"),
  target_date = target_date,
  target_folder = here("rt-forecast", "data", "samples", "hosp"), 
  summary_args = list(summary_dir = here("rt-forecast", "data", "summary",
                                           "hosp", target_date),
                       all_regions = TRUE),
  logs = "rt-forecast/logs/hosp", verbose = TRUE)

plan("sequential")
