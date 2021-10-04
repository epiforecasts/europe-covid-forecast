FROM  docker.pkg.github.com/epiforecasts/epinow2/epinow2:latest


RUN apt-get update -y && \
    apt-get install -y libsecret-1-dev && \
    apt-get clean
    
## Copy files to working directory of server
ADD . europe-covid-forecast

## Set working directory to be this folder
WORKDIR europe-covid-forecast

## Install missing packages
RUN Rscript -e "devtools::install_dev_deps()"
