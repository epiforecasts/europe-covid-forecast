#!bin/bash

# update the Crowd forecast report
Rscript reports/compile-ensemble-report.R

Rscript reports/compile-evaluation-report.R

Rscript reports/update_index_file.R
