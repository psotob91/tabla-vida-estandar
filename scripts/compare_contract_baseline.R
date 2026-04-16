#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
  library(digest)
})

source(here("R", "io_utils.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Uso: Rscript scripts/compare_contract_baseline.R <baseline_dir>")

baseline_dir <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
p <- ensure_standard_life_table_dirs()
out_dir <- p$QC_DIR
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

hash_file <- function(path) if (file.exists(path)) digest::digest(file = path, algo = "md5") else NA_character_
dtype_summary <- function(dt) data.table(column_name = names(dt), class = vapply(dt, function(x) class(x)[1], character(1)), typeof = vapply(dt, typeof, character(1)))
key_uniqueness <- function(dt, keys) dt[, .N, by = keys][N > 1, .N] == 0L

contract_files <- data.table(
  dataset_id = c("abridged", "single_age", "abridged_dict_csv", "single_age_dict_csv"),
  baseline_path = c(
    file.path(baseline_dir, "life_table_standard_reference_abridged.csv"),
    file.path(baseline_dir, "life_table_standard_reference_single_age.csv"),
    file.path(baseline_dir, "life_table_standard_reference_abridged_dictionary_ext.csv"),
    file.path(baseline_dir, "life_table_standard_reference_single_age_dictionary_ext.csv")
  ),
  current_path = c(
    here("data", "final", "standard_life_table", "life_table_standard_reference_abridged.csv"),
    here("data", "final", "standard_life_table", "life_table_standard_reference_single_age.csv"),
    here("data", "final", "standard_life_table", "life_table_standard_reference_abridged_dictionary_ext.csv"),
    here("data", "final", "standard_life_table", "life_table_standard_reference_single_age_dictionary_ext.csv")
  )
)

results <- rbindlist(lapply(seq_len(nrow(contract_files)), function(i) {
  x <- contract_files[i]
  exists_baseline <- file.exists(x$baseline_path)
  exists_current <- file.exists(x$current_path)
  if (!exists_baseline || !exists_current) {
    return(data.table(
      dataset_id = x$dataset_id,
      exists_baseline = exists_baseline,
      exists_current = exists_current,
      rows_baseline = NA_integer_,
      rows_current = NA_integer_,
      columns_equal = NA,
      classes_equal = NA,
      typeof_equal = NA,
      key_unique_current = NA,
      checksum_equal = NA,
      value_change_policy = NA_character_,
      notes = "Falta baseline o output actual."
    ))
  }

  base <- fread(x$baseline_path, encoding = "UTF-8")
  cur <- fread(x$current_path, encoding = "UTF-8")
  base_types <- dtype_summary(base)
  cur_types <- dtype_summary(cur)
  types_cmp <- merge(base_types, cur_types, by = "column_name", suffixes = c("_baseline", "_current"), all = TRUE)
  columns_equal <- identical(names(base), names(cur))
  classes_equal <- nrow(types_cmp[class_baseline != class_current | is.na(class_baseline) | is.na(class_current)]) == 0L
  typeof_equal <- nrow(types_cmp[typeof_baseline != typeof_current | is.na(typeof_baseline) | is.na(typeof_current)]) == 0L
  keys <- if (x$dataset_id == "abridged") c("standard_source", "standard_version", "sex_id", "age_start") else if (x$dataset_id == "single_age") c("standard_source", "standard_version", "sex_id", "exact_age") else character()
  policy <- if (grepl("dict", x$dataset_id, fixed = TRUE)) "dictionary_metadata_may_vary" else "should_match_baseline"
  notes <- if (grepl("dict", x$dataset_id, fixed = TRUE)) "Los diccionarios pueden cambiar de checksum por run_id o metadatos de exportacion, pero deben conservar estructura." else "El baseline ya refleja el contrato final vigente y deberia mantenerse estable."

  data.table(
    dataset_id = x$dataset_id,
    exists_baseline = exists_baseline,
    exists_current = exists_current,
    rows_baseline = nrow(base),
    rows_current = nrow(cur),
    columns_equal = columns_equal,
    classes_equal = classes_equal,
    typeof_equal = typeof_equal,
    key_unique_current = if (length(keys)) key_uniqueness(cur, keys) else NA,
    checksum_equal = identical(hash_file(x$baseline_path), hash_file(x$current_path)),
    value_change_policy = policy,
    notes = notes
  )
}), fill = TRUE)

if (file.exists(contract_files$current_path[contract_files$dataset_id == "single_age"])) {
  base_sa <- fread(contract_files$baseline_path[contract_files$dataset_id == "single_age"], encoding = "UTF-8")
  cur_sa <- fread(contract_files$current_path[contract_files$dataset_id == "single_age"], encoding = "UTF-8")
  value_cmp <- merge(
    base_sa[, .(standard_source, standard_version, sex_id, exact_age, ex_baseline = ex)],
    cur_sa[, .(standard_source, standard_version, sex_id, exact_age, ex_current = ex)],
    by = c("standard_source", "standard_version", "sex_id", "exact_age"),
    all = TRUE
  )
  value_cmp[, diff_ex := ex_current - ex_baseline]
  value_fp <- file.path(out_dir, "baseline_compare_single_age_values.csv")
  fwrite(value_cmp, value_fp)
  if (!file.exists(value_fp)) stop("No se pudo escribir baseline_compare_single_age_values.csv")
}

out_fp <- file.path(out_dir, "baseline_compare_summary.csv")
fwrite(results, out_fp)
if (!file.exists(out_fp)) stop("No se pudo escribir baseline_compare_summary.csv")
message("Comparacion baseline vs contrato final escrita en: ", out_fp)
