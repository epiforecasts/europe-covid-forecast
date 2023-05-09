# Packages -----------------------------------------------------------------
library(covid.ecdc.forecasts)
library(EpiNow2, quietly = TRUE)
library(data.table, quietly = TRUE)
library(future, quietly = TRUE)
library(here, quietly = TRUE)
library(lubridate, quietly = TRUE)

# Set target date ---------------------------------------------------------
target_date <- as.Date(get_forecast_date(dir = here("data-raw")))
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

scale_gamma <- function(dist, scale = 1) {
  return(list(
    mean = scale * dist$mean,
    mean_sd = scale * dist$mean_sd,
    sd = scale * dist$sd,
    sd_sd = scale * dist$sd_sd,
    max = ceiling(scale * dist$max)
  )) 
}

scale_lognormal <- function(dist, scale = 1) {
  return(list(
    mean = dist$mean + log(scale),
    mean_sd = dist$mean_sd,
    sd = dist$sd,
    sd_sd = dist$sd,
    max = ceiling(scale * dist$max)
  ))
}

## convert delays to weekly
generation_time <- scale_gamma(generation_time, 1/7)
incubation_period <- scale_lognormal(incubation_period, 1/7)
onset_to_report <- scale_lognormal(onset_to_report, 1/7)

dir <- c(cases = "ECDC", hospitalizations = "OWID", deaths = "ECDC")
target_variables <- c(cases = "inc case", hospitalizations = "inc hosp", deaths = "inc death")

recommended_cutoffs <- fread(
  here::here("data-raw", "recommended-cutoffs.csv")
)

for (target in c("cases", "hospitalizations", "deaths")) {

  # Get data ---------------------------------------------------------------
  cases <- fread(
    file.path("data-raw", paste0("weekly-incident-", target , ".csv"))
  )
  cases <- cases[, .(region = as.character(location_name),
                   date = as.Date(date), confirm = value)]
  cases <- cases[!is.na(confirm)]
  cases <- cases[confirm < 0, confirm := 0]
  cases <- cases[date >= (max(date) - weeks(12))]
  ## rescale dates
  cases <- cases[, 
    date := target_date + as.integer((date - target_date) / 7)
  ]
  setorder(cases, region, date)

  snapshot_files <- list.files(
    here::here("data-raw", dir[[target]]), full.name = TRUE, 
    pattern = target, ignore.case = TRUE
  )
  snapshot_files <- tail(snapshot_files, 12)

  snapshots <- purrr::map(snapshot_files, \(x) {
    dt <- fread(x)
    dt <- dt[, 
      date := target_date + as.integer(as.Date(date) - target_date) / 7
    ]
  })

  cutoffs <- recommended_cutoffs[target_variable == target_variables[target]]
  no_cutoff <- setdiff(cases$region, cutoffs$location_name)
  trunc_loc <- lapply(unique(cutoffs$location_name), function(loc) {
    loc_snapshots <- lapply(snapshots, function(x) {
      x <- x[location_name == loc][, list(date, confirm = value)]
      x <- x[date > target_date - 20] ## 20 weeks of data
    })
    safe_estimate_truncation <- purrr::safely(estimate_truncation)
    est <- safe_estimate_truncation(loc_snapshots, trunc_max = 3, chains = 2)
    return(est$result$dist)
  })
  failure <- vapply(trunc_loc, is.null, FALSE)
  failed_cutoff_names <- unique(cutoffs$location_name)[failure]
  cutoff_names <- unique(cutoffs$location_name)[!failure]
  trunc_loc <- trunc_loc[!failure]
  names(trunc_loc) <- cutoff_names

  trunc <- opts_list(trunc_opts(), cases)
  trunc[cutoff_names] <- lapply(trunc_loc, trunc_opts)
  trunc[failed_cutoff_names] <- NULL

  loc_names <- names(trunc)
  cases <- cases[region %in% loc_names]

  # Set up parallel execution -----------------------------------------------
  no_cores <- setup_future(cases)

  # Run Rt estimation -------------------------------------------------------
  rt <- opts_list(
    rt_opts(prior = list(mean = 1.0, sd = 0.1)), cases
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
    reported_cases = cases,
    generation_time = generation_time, 
    delays = delay_opts(incubation_period, onset_to_report),
    truncation = trunc,
    rt = rt,
    stan = stan_opts(samples = 2000, warmup = 500,
                     chains = 2, cores = no_cores),
    obs = obs_opts(scale = list(mean = 0.05, sd = 0.025), week_effect = FALSE),
    horizon = 4,
    output = c("region", "summary", "timing", "samples", "fit"),
    target_date = as.character(target_date),
    target_folder = here("rt-forecast", "data", "samples", target), 
    summary_args = list(summary_dir = here("rt-forecast", "data", "summary",
                                             target, target_date),
                         all_regions = TRUE),
    logs = paste0("rt-forecast/logs/", target), verbose = TRUE
  )
}

plan("sequential")
