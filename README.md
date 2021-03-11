# Crowd sourced and model derived forecasts of Covid-19 for the ECDC forecasting hub

*Nikos Bosse\*, Sam Abbott\*, EpiForecasts, and Sebastian Funk*

*\* contributed unequally*

## Introduction 

Forecasting approaches for infectious disease are generally a combination of a statistical or mechanistic modelling framework and expert opinion. The expert opinion is usually that of the modeller responsible for developing the approach, provided via their choices in model tuning and selection. Here, we aim to disentangle the contributions of these factors by comparing a forecast estimated using a minimally tuned semi-mechanistic approach, `EpiNow2`, an ensemble of crowd sourced opinion (both expert and non-expert) `EpiExpert`, and a combined ensemble of both approaches. These forecasts are submitted each week to the ECDC forecasting Covid-19 hub where they are combined with other models to inform policy makers and independently evaluated in the context of other modelling teams submissions.

This project is under development with forecasts being submitted each week.

## Methods

### Data 

Data on test positive Covid-19 cases and deaths linked to Covid-19 were downloaded from the [ECDC](https://www.ecdc.europa.eu/en/covid-19/data) data repository each Monday. The data is subject to reporting artifacts, and changes in reporting and testing regimes. 
 
### Models

[`EpiNow2`](https://epiforecasts.io/EpiNow2/) is an exponential growth model that uses a time-varying Rt trajectory to predict latent infections, and then convolves these infections with estimated delays to reported cases, via a negative binomial model coupled with a day of the week effect. Reported deaths are then forecast using a convolution of forecast cases and a scaling factor, combined with a day of the week effect and a negative binomial reporting model. The method and underlying theory are under active development with more details available [here](https://epiforecasts.io/covid/methods) and [here](https://epiforecasts.io/EpiNow2/dev).

[`EpiExpert`](https://cmmid-lshtm.shinyapps.io/crowd-forecast/) is an ensemble of crowd opinion. Participants were asked to make forecasts using a shiny application (https://cmmid-lshtm.shinyapps.io/crowd-forecast/). In the application they could select a predictive distribution (the default was log-normal) and adjust the median and the width of the uncertainty. The baseline model shown to participants is a model that repeats the last known observation and adds some constant uncertainty based on changes observed in the data in the previous four weeks. Users are able to predict on a logarithmic or linear scale and could use the application to access some information like the test positivity rate, case fatality rate and the number of tests performed in each country. 

### Submission format

Forecasts are submitted every Monday with a one to four week ahead horizon. Forecasts are in a quantile-based formats with 22 quantiles plus the median prediction. 
