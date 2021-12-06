#!/bin/bash

if [ $(date +'%A') = 'Monday' ]; then
  LAST_MONDAY=$(date +'%Y-%m-%d')
else
  LAST_MONDAY=$(date --date='last Mon' +'%Y-%m-%d')
fi
mkdir -p data-processed/epiforecasts-EpiNow2
wget -P data-processed/epiforecasts-EpiNow2 https://raw.githubusercontent.com/epiforecasts/europe-covid-forecast/master/submissions/rt-forecasts/$LAST_MONDAY/$LAST_MONDAY-epiforecasts-EpiNow2.csv
