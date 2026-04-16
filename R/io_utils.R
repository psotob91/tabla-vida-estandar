library(here)

paths_standard_life_table <- function() {
  list(
    RAW_DIR      = here("data", "raw", "standard_life_table"),
    STAGING_DIR  = here("data", "derived", "staging", "standard_life_table"),
    QC_DIR       = here("data", "derived", "qc", "standard_life_table"),
    FINAL_DIR    = here("data", "final", "standard_life_table"),
    REPORTS_DIR  = here("reports"),
    OUTPUTS_DIR  = here("outputs"),
    CONFIG_DIR   = here("config")
  )
}

ensure_standard_life_table_dirs <- function() {
  p <- paths_standard_life_table()
  dirs <- unname(unlist(p[c("RAW_DIR", "STAGING_DIR", "QC_DIR", "FINAL_DIR", "REPORTS_DIR", "OUTPUTS_DIR")]))
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
  p
}

ensure_project_dirs <- function() {
  ensure_standard_life_table_dirs()
}
