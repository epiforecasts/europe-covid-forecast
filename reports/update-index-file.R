rmarkdown::render(here::here("docs", "index.Rmd"),
                  output_format = "html_document",
                  output_dir = here::here("docs"), 
                  output_file = "index.html",
                  envir = new.env())
