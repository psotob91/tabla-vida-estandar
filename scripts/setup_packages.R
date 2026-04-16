#!/usr/bin/env Rscript

required_pkgs <- c(
  "data.table", "dplyr", "readr", "yaml", "here", "janitor",
  "openxlsx", "stringr", "rmarkdown", "knitr", "ggplot2",
  "tinytex", "png", "yaml", "digest", "jsonlite", "plotly"
)

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
}

invisible(lapply(required_pkgs, library, character.only = TRUE))

source(here::here("R", "io_utils.R"))
source(here::here("R", "catalog_utils.R"))
source(here::here("R", "spec_utils.R"))
source(here::here("R", "dictionary_utils.R"))
source(here::here("R", "qc_standard_life_table_utils.R"))
source(here::here("R", "standard_life_table_tail_utils.R"))

ensure_standard_life_table_dirs()
ensure_catalog_files()

message("Paquetes y utilitarios listos para tabla de vida estandar.")
