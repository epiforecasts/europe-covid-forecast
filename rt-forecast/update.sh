#!bin/bash

# Update the input data
Rscript data-raw/update.R

# Update cases forecast
Rscript rt-forecast/case-hosp-death.R

# Update submissions
Rscript rt-forecast/submission.R
