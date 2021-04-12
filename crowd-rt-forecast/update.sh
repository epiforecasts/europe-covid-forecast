#!bin/bash

# Update Rt crowd forecast samples
Rscript crowd-rt-forecast/extract-samples.R

# Simulate cases from Rt crowd forecast
Rscript crowd-rt-forecast/simulate-targets.R

# Redeploy Rt forecast app (to update submission date to next week)
Rscript crowd-rt-forecast/redeploy.R
