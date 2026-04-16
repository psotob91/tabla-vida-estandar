#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
  library(ggplot2)
  library(rmarkdown)
  library(tinytex)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))
source(here("R", "qc_standard_life_table_utils.R"))
source(here("R", "standard_life_table_tail_utils.R"))

DATASET_ID <- "life_table_standard_reference_single_age"
VERSION <- "v2.0.0"
TABLE_NAME <- "life_table_standard_single_age_result"
TERMINAL_AGE <- 110L
SUPPORT_AGE_MAX <- 125L

ensure_pandoc_for_rmarkdown <- function() {
  if (isTRUE(rmarkdown::pandoc_available())) return(invisible(TRUE))
  quarto_bin <- unname(Sys.which("quarto"))
  if (!nzchar(quarto_bin)) return(invisible(FALSE))
  quarto_pandoc_dir <- file.path(dirname(quarto_bin), "tools")
  quarto_pandoc <- file.path(quarto_pandoc_dir, "pandoc.exe")
  if (file.exists(quarto_pandoc)) {
    pandoc_dir <- normalizePath(quarto_pandoc_dir, winslash = "/", mustWork = TRUE)
    Sys.setenv(RSTUDIO_PANDOC = pandoc_dir)
    Sys.setenv(PATH = paste(pandoc_dir, Sys.getenv("PATH"), sep = .Platform$path.sep))
  }
  invisible(rmarkdown::pandoc_available())
}

run_id <- paste0("qc_standard_life_table_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id = run_id, dataset_id = DATASET_ID, version = VERSION)

fail_run <- function(e) {
  register_run_finish(run_id, status = "failed", message = conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  abr <- fread(file.path(p$STAGING_DIR, "life_table_standard_abridged.csv"), encoding = "UTF-8")
  sa <- fread(file.path(p$STAGING_DIR, "life_table_standard_single_age.csv"), encoding = "UTF-8")
  setDT(abr); setDT(sa)

  qc_abr <- qc_standard_life_table_abridged(abr)
  qc_sa <- qc_standard_life_table_single_age(sa, terminal_age = TERMINAL_AGE, monotone_versions = MONOTONE_STANDARD_VERSIONS)
  qc_knot <- qc_standard_knot_preservation_single_age(sa, abr)
  terminal_summary <- summarise_standard_terminal_interval(sa, abr, terminal_age = TERMINAL_AGE, support_age_max = SUPPORT_AGE_MAX, monotone_versions = MONOTONE_STANDARD_VERSIONS)
  qc_terminal <- qc_standard_terminal_interval(terminal_summary, terminal_age = TERMINAL_AGE, expect_positive_open_ex = TRUE)

  method_detail_fp <- file.path(p$QC_DIR, "single_age_tail_method_detail.csv")
  method_selected_fp <- file.path(p$QC_DIR, "single_age_tail_selected_methods.csv")
  compare_fp <- file.path(p$QC_DIR, "single_age_tail_final_vs_exspace.csv")
  method_detail <- if (file.exists(method_detail_fp)) fread(method_detail_fp) else data.table()
  selected_methods <- if (file.exists(method_selected_fp)) fread(method_selected_fp) else data.table()
  compare_dt <- if (file.exists(compare_fp)) fread(compare_fp) else data.table()

  summary_abr <- data.table(check_name = names(qc_abr), n_rows = vapply(qc_abr, nrow, integer(1)), dataset = "abridged")
  summary_sa <- data.table(check_name = c(names(qc_sa), "knot_preservation", paste0("terminal_", names(qc_terminal))),
                           n_rows = c(vapply(qc_sa, nrow, integer(1)), nrow(qc_knot), vapply(qc_terminal, nrow, integer(1))),
                           dataset = "single_age")
  summary_all <- rbind(summary_abr, summary_sa, fill = TRUE)
  summary_all[, status := fifelse(n_rows == 0L, "OK", "HALLAZGO")]
  setcolorder(summary_all, c("dataset", "check_name", "status", "n_rows"))

  write_qc <- function(dt, fp, notes = "Archivo QC de tabla de vida estandar.") {
    fwrite(dt, fp)
    register_artifact(DATASET_ID, TABLE_NAME, VERSION, run_id, "qc", fp, nrow(dt), ncol(dt), notes)
  }

  for (nm in names(qc_abr)) write_qc(as.data.table(qc_abr[[nm]]), file.path(p$QC_DIR, paste0("qc_standard_life_table_abridged_", nm, ".csv")))
  for (nm in names(qc_sa)) write_qc(as.data.table(qc_sa[[nm]]), file.path(p$QC_DIR, paste0("qc_standard_life_table_single_age_", nm, ".csv")))
  for (nm in names(qc_terminal)) write_qc(as.data.table(qc_terminal[[nm]]), file.path(p$QC_DIR, paste0("qc_standard_life_table_terminal_", nm, ".csv")))
  write_qc(qc_knot, file.path(p$QC_DIR, "qc_standard_life_table_knot_preservation.csv"))
  write_qc(summary_all, file.path(p$QC_DIR, "qc_standard_life_table_summary.csv"))
  write_qc(terminal_summary, file.path(p$QC_DIR, "qc_standard_life_table_terminal_summary.csv"))

  plot_dt <- merge(
    sa[, .(standard_source, standard_version, sex_source_value, exact_age, ex_final = ex)],
    abr[abs(age_start - round(age_start)) < 1e-8, .(standard_source, standard_version, sex_source_value, exact_age = as.integer(round(age_start)), ex_abridged = ex)],
    by = c("standard_source", "standard_version", "sex_source_value", "exact_age"),
    all = TRUE
  )

  p_curve <- ggplot() +
    geom_line(data = sa, aes(exact_age, ex, color = sex_source_value, group = interaction(standard_source, standard_version, sex_source_value))) +
    geom_point(data = abr[abs(age_start - round(age_start)) < 1e-8], aes(age_start, ex, color = sex_source_value), shape = 21, fill = "white", stroke = 0.8) +
    facet_grid(sex_source_value ~ standard_source + standard_version, scales = "free_y") +
    labs(title = "e(x) final y knots abridged", subtitle = "La salida contractual final mantiene 110+ abierto con ex positiva derivada desde la cola 110:125.", x = "Edad simple", y = "e(x)", color = "Sexo") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom", strip.text = element_text(size = 8))

  plot_fp <- file.path(p$QC_DIR, "qc_standard_life_table_ex_comparison.png")
  ggsave(plot_fp, p_curve, width = 14, height = 8.5, units = "in", dpi = 300, bg = "white")
  register_artifact(DATASET_ID, TABLE_NAME, VERSION, run_id, "qc", plot_fp, notes = "Comparacion entre la curva final y los knots abridged.")

  tiny_root <- tryCatch(tinytex::tinytex_root(), error = function(e) "")
  tiny_bin_candidates <- unique(c(if (nzchar(tiny_root)) file.path(tiny_root, "bin", "windows") else character(0), "C:/Users/Usuario/AppData/Roaming/TinyTeX/bin/windows"))
  tiny_bin_candidates <- tiny_bin_candidates[dir.exists(tiny_bin_candidates)]
  if (length(tiny_bin_candidates) > 0) Sys.setenv(PATH = paste(paste(tiny_bin_candidates, collapse = .Platform$path.sep), Sys.getenv("PATH"), sep = .Platform$path.sep))
  if (!nzchar(Sys.which("pdflatex"))) stop("No se encontro pdflatex en el PATH activo.")
  if (!ensure_pandoc_for_rmarkdown()) stop("No se encontro Pandoc para renderizar el PDF de QC.")

  tmp_dir <- file.path(p$QC_DIR, paste0("tmp_qc_standard_life_table_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  fwrite(summary_all, file.path(tmp_dir, "summary_all.csv"))
  fwrite(terminal_summary, file.path(tmp_dir, "terminal_summary.csv"))
  fwrite(qc_knot, file.path(tmp_dir, "qc_knot.csv"))
  fwrite(head(sa[order(standard_source, standard_version, sex_id, exact_age)], 60), file.path(tmp_dir, "preview_sa.csv"))
  fwrite(head(abr[order(standard_source, standard_version, sex_id, age_start)], 40), file.path(tmp_dir, "preview_abr.csv"))
  fwrite(selected_methods, file.path(tmp_dir, "selected_methods.csv"))
  fwrite(head(compare_dt[order(standard_source, standard_version, sex_id, exact_age)], 80), file.path(tmp_dir, "compare_dt.csv"))
  rmd_path <- file.path(tmp_dir, "qc_standard_life_table.Rmd")
  pdf_out <- file.path(p$REPORTS_DIR, "qc_standard_life_table.pdf")

  writeLines(c(
    "---",
    "title: \"QC - Tabla de vida estandar\"",
    "author: \"Pipeline tabla-vida-estandar\"",
    "date: \"`r format(Sys.time(), '%Y-%m-%d %H:%M')`\"",
    "output:",
    "  pdf_document:",
    "    toc: true",
    "    number_sections: true",
    "fontsize: 11pt",
    "geometry: margin=1in",
    "header-includes:",
    "  - \\usepackage{longtable}",
    "  - \\usepackage{booktabs}",
    "---",
    "",
    "```{r setup, include=FALSE}",
    "library(data.table)",
    "library(knitr)",
    "options(knitr.kable.NA = '')",
    sprintf("summary_all <- fread('%s')", normalizePath(file.path(tmp_dir, "summary_all.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("terminal_summary <- fread('%s')", normalizePath(file.path(tmp_dir, "terminal_summary.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("qc_knot <- fread('%s')", normalizePath(file.path(tmp_dir, "qc_knot.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("preview_sa <- fread('%s')", normalizePath(file.path(tmp_dir, "preview_sa.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("preview_abr <- fread('%s')", normalizePath(file.path(tmp_dir, "preview_abr.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("selected_methods <- fread('%s')", normalizePath(file.path(tmp_dir, "selected_methods.csv"), winslash = "/", mustWork = FALSE)),
    sprintf("compare_dt <- fread('%s')", normalizePath(file.path(tmp_dir, "compare_dt.csv"), winslash = "/", mustWork = FALSE)),
    "```",
    "",
    "# Resumen global",
    "```{r}",
    "kable(summary_all, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Politica terminal",
    "```{r}",
    "kable(terminal_summary, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Metodo final y benchmark",
    "```{r}",
    "kable(selected_methods, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Preservacion de knots",
    "```{r}",
    "if (nrow(qc_knot) == 0) cat('Sin hallazgos.\\n') else kable(qc_knot, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Muestra abridged",
    "```{r}",
    "kable(preview_abr, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Muestra single-age final",
    "```{r}",
    "kable(preview_sa, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Diferencia entre metodo final y benchmark ex-space",
    "```{r}",
    "kable(compare_dt, format = 'latex', booktabs = TRUE, longtable = TRUE)",
    "```",
    "",
    "# Figura principal",
    "```{r, out.width='100%'}",
    sprintf("knitr::include_graphics('%s')", normalizePath(plot_fp, winslash = "/", mustWork = FALSE)),
    "```"
  ), con = rmd_path, useBytes = TRUE)

  rmarkdown::render(input = rmd_path, output_file = basename(pdf_out), output_dir = dirname(pdf_out), quiet = TRUE, envir = new.env(parent = globalenv()))
  register_artifact(DATASET_ID, TABLE_NAME, VERSION, run_id, "report", pdf_out, notes = "Reporte PDF de QC de tabla de vida estandar.")

  register_run_finish(run_id, status = "success")
  message("QC completado: ", pdf_out)
}, error = fail_run)
