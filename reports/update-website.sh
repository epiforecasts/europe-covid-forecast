#!/bin/bash

Rscript reports/compile-ensemble-report.R    
Rscript reports/compile-evaluation-report.R
Rscript reports/compile-uk-challenge-report.R
Rscript reports/update-index-file.R


# copy files over to crowd-evaluation repo and push
cd ..

cp -R -f "europe-covid-forecast/docs/index.html" "crowd-evaluation/"

cp -R -f "europe-covid-forecast/docs/reports" "crowd-evaluation/"

cd crowd-evaluation 

git add .

git commit -m "automated update - evaluation reports"

git pull

git push

cd ..

cd europe-covid-forecast

# copy files over to uk-challenge repo and push

cd ..

cp "europe-covid-forecast/docs/reports/uk-challenge/index.html" "uk-challenge"

cd uk-challenge
git add .
git commit -m "automated update - evaluation report"
git pull
git push
cd ..
cd europe-covid-forecast

