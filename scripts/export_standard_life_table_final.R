#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
  library(openxlsx)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))
source(here("R", "spec_utils.R"))
source(here("R", "dictionary_utils.R"))

export_with_catalog <- function(dt, dict, out_stem, final_dir, dataset_id, table_name, version, run_id, notes) {
  csv_fp <- file.path(final_dir, paste0(out_stem, ".csv"))
  rds_fp <- file.path(final_dir, paste0(out_stem, ".rds"))
  xlsx_fp <- file.path(final_dir, paste0(out_stem, "_dictionary_ext.xlsx"))
  dict_csv <- file.path(final_dir, paste0(out_stem, "_dictionary_ext.csv"))

  fwrite(as.data.table(dt), csv_fp)
  saveRDS(dt, rds_fp)
  openxlsx::write.xlsx(dict, xlsx_fp, overwrite = TRUE)
  fwrite(as.data.table(dict), dict_csv)

  for (fp in c(csv_fp, rds_fp)) {
    register_artifact(dataset_id, table_name, version, run_id, "final_dataset", fp, nrow(dt), ncol(dt), notes)
  }
  for (fp in c(xlsx_fp, dict_csv)) {
    register_artifact(dataset_id, table_name, version, run_id, "dictionary_ext", fp, nrow(dict), ncol(dict), "Diccionario extendido derivado del spec final.")
  }
}

DATASET_ID_ABR <- "life_table_standard_reference_abridged"
DATASET_ID_SA <- "life_table_standard_reference_single_age"
VERSION <- "v2.0.0"
TABLE_ABR <- "life_table_standard_abridged_result"
TABLE_SA <- "life_table_standard_single_age_result"

run_id <- paste0("export_standard_life_table_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id = run_id, dataset_id = DATASET_ID_SA, version = VERSION)

fail_run <- function(e) {
  register_run_finish(run_id, status = "failed", message = conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  abr <- fread(file.path(p$STAGING_DIR, "life_table_standard_abridged.csv"), encoding = "UTF-8")
  sa <- fread(file.path(p$STAGING_DIR, "life_table_standard_single_age.csv"), encoding = "UTF-8")
  spec_abr <- read_spec(file.path(p$CONFIG_DIR, "spec_life_table_standard_abridged.yml"))
  spec_sa <- read_spec(file.path(p$CONFIG_DIR, "spec_life_table_standard_single_age.yml"))

  validate_by_spec(abr, spec_abr)
  validate_by_spec(sa, spec_sa)

  dict_abr <- enrich_dict_with_stats(dict_from_spec(spec_abr, dataset_version = VERSION, run_id = run_id, config_dir = p$CONFIG_DIR), abr)
  dict_sa <- enrich_dict_with_stats(dict_from_spec(spec_sa, dataset_version = VERSION, run_id = run_id, config_dir = p$CONFIG_DIR), sa)

  export_with_catalog(abr, dict_abr, "life_table_standard_reference_abridged", p$FINAL_DIR, DATASET_ID_ABR, TABLE_ABR, VERSION, run_id, "Output contractual final abridged.")
  export_with_catalog(sa, dict_sa, "life_table_standard_reference_single_age", p$FINAL_DIR, DATASET_ID_SA, TABLE_SA, VERSION, run_id, "Output contractual final single-age con 110+ abierto y ex positiva.")

  knot_cmp <- merge(
    abr[abs(age_start - round(age_start)) < 1e-8, .(standard_source, standard_version, sex_id, sex_source_value, exact_age = as.integer(round(age_start)), ex_abridged = ex)],
    sa[, .(standard_source, standard_version, sex_id, sex_source_value, exact_age, ex_single_age = ex)],
    by = c("standard_source", "standard_version", "sex_id", "sex_source_value", "exact_age"),
    all.x = TRUE
  )
  knot_cmp[, abs_diff := abs(ex_abridged - ex_single_age)]
  knot_summary <- knot_cmp[, .(
    n_knots = .N,
    n_missing_single_age = sum(is.na(ex_single_age)),
    max_abs_diff = max(abs_diff, na.rm = TRUE),
    mean_abs_diff = mean(abs_diff, na.rm = TRUE)
  ), by = .(standard_source, standard_version, sex_id, sex_source_value)]
  export_summary <- data.table(
    metric = c("N filas abridged", "N filas single_age", "N estratos abridged", "N estratos single_age", "ex(110+) minima", "ex(110+) maxima"),
    value = c(
      as.character(nrow(abr)),
      as.character(nrow(sa)),
      as.character(uniqueN(abr[, .(standard_source, standard_version, sex_id, sex_source_value)])),
      as.character(uniqueN(sa[, .(standard_source, standard_version, sex_id, sex_source_value)])),
      as.character(min(sa[exact_age == 110L, ex], na.rm = TRUE)),
      as.character(max(sa[exact_age == 110L, ex], na.rm = TRUE))
    )
  )

  fwrite(knot_cmp, file.path(p$QC_DIR, "export_knot_comparison.csv"))
  fwrite(knot_summary, file.path(p$QC_DIR, "export_knot_comparison_summary.csv"))
  fwrite(export_summary, file.path(p$QC_DIR, "export_summary.csv"))
  fwrite(knot_summary, file.path(p$QC_DIR, "qc_standard_life_table_knot_comparison_summary.csv"))
  register_artifact(DATASET_ID_SA, TABLE_SA, VERSION, run_id, "qc", file.path(p$QC_DIR, "export_knot_comparison.csv"), nrow(knot_cmp), ncol(knot_cmp), "Comparacion de knots exportada a QC.")
  register_artifact(DATASET_ID_SA, TABLE_SA, VERSION, run_id, "qc", file.path(p$QC_DIR, "export_knot_comparison_summary.csv"), nrow(knot_summary), ncol(knot_summary), "Resumen por estrato de comparacion de knots.")
  register_artifact(DATASET_ID_SA, TABLE_SA, VERSION, run_id, "qc", file.path(p$QC_DIR, "qc_standard_life_table_knot_comparison_summary.csv"), nrow(knot_summary), ncol(knot_summary), "Resumen por estrato de comparacion de knots para lectores heredados.")
  register_artifact(DATASET_ID_SA, TABLE_SA, VERSION, run_id, "qc", file.path(p$QC_DIR, "export_summary.csv"), nrow(export_summary), ncol(export_summary), "Resumen de export final.")

  register_run_finish(run_id, status = "success")
  message("Export final completado en: ", p$FINAL_DIR)
}, error = fail_run)
