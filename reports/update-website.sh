#!/bin/bash

Rscript reports/compile-ensemble-report.R    
Rscript reports/compile-evaluation-report.R

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
