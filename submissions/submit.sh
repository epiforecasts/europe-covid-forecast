#!/bin/bash

#define date
ForecastDate=$(date +'%Y-%m-%d')

# Clone the hub repository if not already present
#git clone --depth 1 https://github.com/epiforecasts/covid19-forecast-hub-europe

# install GitHub CLI
# https://cli.github.com/

# Authenticate with GitHub
# gh auth login

# Update the hub repository
cd ../covid19-forecast-hub-europe
git checkout main
git pull 
# Switch to submission branch
git checkout -b submission1
git merge -Xtheirs main

# Move back into forecast repository
cd ../europe-covid-forecast

# Copy your forecast from local folder to submission folder
cp -R -f "./submissions/rt-forecasts/$ForecastDate/." \
      "../covid19-forecast-hub-europe/data-processed/epiforecasts-EpiNow2/"
cp -R -f "./submissions/crowd-rt-forecasts/$ForecastDate/." \
      "../covid19-forecast-hub-europe/data-processed/epiforecasts-EpiExpert_Rt/"
cp -R -f "./submissions/crowd-direct-forecasts/$ForecastDate/." \
      "../covid19-forecast-hub-europe/data-processed/epiforecasts-EpiExpert_direct/"
cp -R -f "./submissions/crowd-forecasts/$ForecastDate/." \
      "../covid19-forecast-hub-europe/data-processed/epiforecasts-EpiExpert/"
      
# Commit submission to branch
cd ../covid19-forecast-hub-europe
git add --all
git commit -m "submission"

# Create PR
gh pr create --title "$ForecastDate - EpiForecast submission" --body " This is an automated submission."

# Remove local submission branch 
git checkout main
git branch -D submission1
cd ../europe-covid-forecast
