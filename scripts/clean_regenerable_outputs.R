#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(here)
  library(data.table)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))

dry_run <- tolower(Sys.getenv("CLEAN_DRY_RUN", unset = "true")) != "false"
confirmed <- identical(Sys.getenv("CLEAN_CONFIRM", unset = ""), "YES")

targets <- list(
  list(kind = "dir_contents", path = here("data", "final"), note = "datasets finales regenerables"),
  list(kind = "dir_contents", path = here("data", "derived", "staging"), note = "staging regenerable"),
  list(kind = "dir_contents", path = here("data", "derived", "qc", "run_pipeline"), note = "QC operativo regenerable"),
  list(kind = "dir_contents", path = here("data", "derived", "qc", "standard_life_table"), note = "QC tabular y comparaciones regenerables; preserva baseline_contract*"),
  list(kind = "dir_contents", path = here("data", "_catalog"), note = "catalogos y provenance regenerables"),
  list(kind = "dir_contents", path = here("outputs"), note = "salidas auxiliares regenerables"),
  list(kind = "dir_contents", path = here("reports", "qc_standard_life_table"), note = "portal y tomos regenerables"),
  list(kind = "dir_filtered", path = here("reports"), note = "renderizados HTML/PDF regenerables; preserva fuentes .qmd", keep_pattern = "\\.qmd$")
)

collect_targets <- function(spec) {
  if (!dir.exists(spec$path)) return(character())
  kids <- list.files(spec$path, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (identical(spec$kind, "dir_contents")) {
    protected <- grepl("baseline_contract", basename(kids), fixed = TRUE)
    return(kids[!protected])
  }
  if (identical(spec$kind, "dir_filtered")) return(kids[!grepl(spec$keep_pattern, basename(kids), perl = TRUE)])
  character()
}

target_rows <- rbindlist(lapply(targets, function(spec) {
  paths <- collect_targets(spec)
  data.table(
    rule_kind = spec$kind,
    root_path = normalizePath(spec$path, winslash = "/", mustWork = FALSE),
    target_path = normalizePath(paths, winslash = "/", mustWork = FALSE),
    note = spec$note
  )
}), fill = TRUE)

cat("Limpieza de artefactos regenerables\n")
cat("Modo dry-run:", dry_run, "\n")
cat("Confirmado:", confirmed, "\n\n")

if (nrow(target_rows) == 0L) {
  cat("No se detectaron artefactos regenerables en las rutas objetivo.\n")
} else {
  summary_dt <- target_rows[, .N, by = .(root_path, note)][order(root_path)]
  for (i in seq_len(nrow(summary_dt))) cat(" - ", summary_dt$root_path[i], " => ", summary_dt$N[i], " artefactos\n", sep = "")
}

if (dry_run || !confirmed) {
  cat("\nNo se elimino nada. Para limpiar de verdad usar:\n")
  cat("  CLEAN_DRY_RUN=false CLEAN_CONFIRM=YES Rscript scripts/clean_regenerable_outputs.R\n")
  quit(save = "no", status = 0)
}

for (tp in unique(target_rows$target_path)) if (nzchar(tp) && file.exists(tp)) unlink(tp, recursive = TRUE, force = TRUE)

invisible(ensure_project_dirs())
invisible(ensure_catalog_files())

cat("\nLimpieza completada.\n")
