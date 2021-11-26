#!/bin/bash

TODAY=$(date +'%Y-%m-%d')
mkdir -p data-processed/epiforecasts-EpiNow2
wget -P data-processed/epiforecasts-EpiNow2 https://raw.githubusercontent.com/epiforecasts/europe-covid-forecast/master/submissions/rt-forecasts/$TODAY/$TODAY-epiforecasts-EpiNow2.csv
