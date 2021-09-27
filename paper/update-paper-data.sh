#!bin/bash

# this requires subversion to be installed

## Move out one directory and clone (or pull) data repo
cd paper
printf "Cloning forecasts folder\n"
svn checkout https://github.com/epiforecasts/covid19-forecast-hub-europe/trunk/data-processed/epiforecasts-EpiExpert_direct
svn checkout https://github.com/epiforecasts/covid19-forecast-hub-europe/trunk/data-processed/epiforecasts-EpiExpert
svn checkout https://github.com/epiforecasts/covid19-forecast-hub-europe/trunk/data-processed/epiforecasts-EpiExpert_Rt
svn checkout https://github.com/epiforecasts/covid19-forecast-hub-europe/trunk/data-processed/EuroCOVIDhub-baseline
svn checkout https://github.com/epiforecasts/covid19-forecast-hub-europe/trunk/data-processed/EuroCOVIDhub-ensemble

cd ..

