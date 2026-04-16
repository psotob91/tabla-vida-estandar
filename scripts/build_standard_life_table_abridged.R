#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(janitor)
  library(here)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))
source(here("R", "spec_utils.R"))

DATASET_ID <- "life_table_standard_reference_abridged"
VERSION <- "v2.0.0"
TABLE_NAME <- "life_table_standard_abridged_result"
RAW_FILE <- "life_expectancy_standard_who_gbd.csv"

run_id <- paste0("build_abridged_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id = run_id, dataset_id = DATASET_ID, version = VERSION)

fail_run <- function(e) {
  register_run_finish(run_id, status = "failed", message = conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  spec <- read_spec(file.path(p$CONFIG_DIR, "spec_life_table_standard_abridged.yml"))
  raw_path <- file.path(p$RAW_DIR, RAW_FILE)
  if (!file.exists(raw_path)) stop("No se encontro el archivo fuente en: ", raw_path)

  dt_raw <- fread(raw_path, encoding = "UTF-8")
  setnames(dt_raw, names(dt_raw), janitor::make_clean_names(names(dt_raw)))

  dt <- dt_raw[, .(
    standard_source = trimws(as.character(standard_source)),
    standard_version = trimws(as.character(standard_version)),
    sex_id = as.integer(sex_concept_id),
    sex_source_value = trimws(as.character(sex)),
    age_start = as.numeric(age_group_start),
    age_end = as.numeric(age_group_end),
    age_group_label = trimws(as.character(age_group_label)),
    ex = as.numeric(life_expectancy),
    units = trimws(as.character(units))
  )]

  dt[is.na(age_group_label) | age_group_label == "", age_group_label := paste0(age_start, "-", age_end)]
  dt[is.na(units) | units == "", units := "years"]
  dt[, age_interval_width := age_end - age_start]
  if (dt[, any(age_interval_width < 0, na.rm = TRUE)]) stop("Hay intervalos con age_end < age_start.")

  sex_ok <- dt[, all(
    (sex_id == 0 & sex_source_value == "Persons") |
      (sex_id == 8507 & sex_source_value == "Male") |
      (sex_id == 8532 & sex_source_value == "Female")
  )]
  if (!sex_ok) stop("Inconsistencia entre sex_id y sex_source_value en la fuente.")

  dt[, age_interval_open := FALSE]
  dt[grepl("\\+$", age_group_label), age_interval_open := TRUE]
  dt[, has_open_label := any(age_interval_open), by = .(standard_source, standard_version, sex_id)]
  dt[has_open_label == FALSE, age_interval_open := age_end == max(age_end, na.rm = TRUE), by = .(standard_source, standard_version, sex_id)]
  dt[, has_open_label := NULL]

  chk_open <- dt[, .(n_open = sum(age_interval_open, na.rm = TRUE)), by = .(standard_source, standard_version, sex_id)]
  if (chk_open[, any(n_open != 1L)]) {
    print(chk_open[n_open != 1L])
    stop("Cada combinacion debe tener exactamente un intervalo abierto final.")
  }

  setorderv(dt, c("standard_source", "standard_version", "sex_id", "age_start"))
  validate_by_spec(dt, spec)

  out_csv <- file.path(p$STAGING_DIR, "life_table_standard_abridged.csv")
  fwrite(dt, out_csv, na = "")

  register_artifact(
    dataset_id = DATASET_ID,
    table_name = TABLE_NAME,
    version = VERSION,
    run_id = run_id,
    artifact_type = "staging",
    artifact_path = out_csv,
    n_rows = nrow(dt),
    n_cols = ncol(dt),
    notes = "Tabla de vida estandar abridged normalizada a estructura OMOP-like."
  )

  register_run_finish(run_id, status = "success")
  message("Abridged normalizada: ", out_csv)
}, error = fail_run)
