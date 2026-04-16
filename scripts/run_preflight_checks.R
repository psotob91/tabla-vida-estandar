#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
})

source(here("R", "io_utils.R"))

out_dir <- here("data", "derived", "qc", "run_pipeline")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

checks <- list()
add_check <- function(check_id, severity, status, path = NA_character_, detail = NA_character_) {
  checks[[length(checks) + 1L]] <<- data.table(
    check_id = check_id,
    severity = severity,
    status = status,
    resolved_path = path,
    detail = detail
  )
}

is_readable <- function(path) file.exists(path) && file.access(path, 4) == 0
is_writable_dir <- function(path) dir.exists(path) && file.access(path, 2) == 0

p <- ensure_standard_life_table_dirs()
add_check("project_root", "blocking", if (dir.exists(here())) "ok" else "fail", here(), "Raiz del proyecto detectada por here().")
add_check("raw_standard_life_table_source", "blocking", if (is_readable(file.path(p$RAW_DIR, "life_expectancy_standard_who_gbd.csv"))) "ok" else "fail", file.path(p$RAW_DIR, "life_expectancy_standard_who_gbd.csv"), "Fuente cruda principal de tabla de vida estandar.")

for (cfg in c(
  file.path(p$CONFIG_DIR, "maestro_sex_omop.csv"),
  file.path(p$CONFIG_DIR, "spec_life_table_standard_abridged.yml"),
  file.path(p$CONFIG_DIR, "spec_life_table_standard_single_age.yml"),
  file.path(p$CONFIG_DIR, "pipeline_steps.csv"),
  file.path(p$CONFIG_DIR, "pipeline_profiles.yml")
)) {
  add_check(paste0("config_", basename(cfg)), "blocking", if (is_readable(cfg)) "ok" else "fail", cfg, "Archivo de configuracion requerido.")
}

for (wd in c(p$STAGING_DIR, p$QC_DIR, p$FINAL_DIR, p$REPORTS_DIR, p$OUTPUTS_DIR, here("data", "_catalog"))) {
  dir.create(wd, recursive = TRUE, showWarnings = FALSE)
  add_check(paste0("writable_", basename(wd)), "blocking", if (is_writable_dir(wd)) "ok" else "fail", wd, "Directorio de salida escribible.")
}

checks_dt <- rbindlist(checks, fill = TRUE)
summary_dt <- checks_dt[, .N, by = .(severity, status)][order(severity, status)]
fwrite(checks_dt, file.path(out_dir, "preflight_checks.csv"))
fwrite(summary_dt, file.path(out_dir, "preflight_summary.csv"))

blocking_bad <- checks_dt[severity == "blocking" & status != "ok"]
if (nrow(blocking_bad) > 0L) {
  message("Preflight NO APROBADO. Revisar data/derived/qc/run_pipeline/preflight_checks.csv")
  quit(save = "no", status = 1)
}

message("Preflight APROBADO.")
