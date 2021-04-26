# Packages ----------------------------------------------------------------
library(EpiNow2, quietly = TRUE)
library(covidregionaldata, quietly = TRUE)
library(data.table, quietly = TRUE)
library(future, quietly = TRUE)
library(here, quietly = TRUE)

# Save incubation period and generation time ------------------------------
shape <- 6.8004
rate <- 1.2344
generation_time <- list(mean = shape / rate, 
                        mean_sd = 0.5,
                        sd = sqrt(shape) / rate,
                        sd_sd = 0.25,
                        max = 15)
incubation_period <- get_incubation_period(
    disease = "SARS-CoV-2", source = "lauer", max_value = 15
    )
saveRDS(generation_time , 
        here("rt-forecast", "data", "delays", "generation_time.rds"))
saveRDS(incubation_period, 
        here("rt-forecast", "data", "delays", "incubation_period.rds"))

# Set up parallel ---------------------------------------------------------
plan("multiprocess")

# get linelist ------------------------------------------------------------
linelist <- as.data.table(covidregionaldata::get_linelist(clean = TRUE))
linelist <- linelist[delay_onset_report < 0, delay_onset_report := NA]
linelist <- linelist[delay_onset_report > 30, delay_onset_report := NA]
linelist <- linelist[!is.na(delay_onset_report)][country %in% "Germany"]

# Fit delay from onset to admission ---------------------------------------
report_delay <- linelist$delay_onset_report
samples <- round(length(report_delay) / 100)
onset_to_report <- estimate_delay(report_delay,
                                  bootstraps = 10, bootstrap_samples = samples,
                                  max_value = 15)
saveRDS(
    onset_to_report, 
    here("rt-forecast", "data", "delays", "onset_to_report.rds"))

