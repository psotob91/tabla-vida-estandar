#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(here)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))

run_id <- paste0("standard_life_table_terminal_module_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id, "standard_life_table", "standard_life_table_terminal_module_v1")

fail_run <- function(e) {
  register_run_finish(run_id, "failed", conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  portal_dir <- file.path(p$REPORTS_DIR, "qc_standard_life_table")
  plot_dir <- file.path(portal_dir, "plots")
  download_dir <- file.path(portal_dir, "downloads")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)

  abr <- fread(file.path(p$FINAL_DIR, "life_table_standard_reference_abridged.csv"))
  sa <- fread(file.path(p$FINAL_DIR, "life_table_standard_reference_single_age.csv"))
  terminal_summary <- fread(file.path(p$QC_DIR, "qc_standard_life_table_terminal_summary.csv"))
  selected_methods <- fread(file.path(p$QC_DIR, "single_age_tail_selected_methods.csv"))
  support_ex <- fread(file.path(p$QC_DIR, "single_age_tail_support_ex_space_to_125.csv"))
  support_law <- fread(file.path(p$QC_DIR, "single_age_tail_support_law_to_125.csv"))

  slug <- function(x) {
    x <- tolower(iconv(as.character(x), to = "ASCII//TRANSLIT", sub = ""))
    x <- gsub("[^a-z0-9]+", "-", x)
    gsub("(^-|-$)", "", x)
  }
  esc <- function(x) {
    x <- as.character(x)
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub('"', "&quot;", x, fixed = TRUE)
  }
  rel <- function(path) sub(paste0("^", normalizePath(portal_dir, winslash = "/", mustWork = FALSE), "/"), "", normalizePath(path, winslash = "/", mustWork = FALSE))
  pal <- c(Female = "#CC79A7", Male = "#0072B2", Persons = "#009E73")
  tportal <- function() theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = "#E6ECF2"), plot.title = element_text(face = "bold", size = 13, color = "#102A43"), plot.subtitle = element_text(size = 9.5, color = "#486581"), axis.text = element_text(color = "#334E68"), axis.title = element_text(color = "#102A43"), legend.position = "bottom")

  strata <- unique(sa[, .(standard_source, standard_version, sex_id, sex_source_value)])
  manifest <- vector("list", nrow(strata))
  sections <- character()
  page_name <- "cola_terminal_110plus.html"

  for (i in seq_len(nrow(strata))) {
    z <- strata[i]
    sid <- slug(paste(z$standard_source, z$standard_version, z$sex_source_value))
    final_tail <- sa[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value & exact_age >= 75]
    ex_tail <- support_ex[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value & exact_age >= 75]
    law_tail <- support_law[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value & exact_age >= 75]

    curve_dt <- rbind(
      data.table(version = "Contractual final", exact_age = final_tail$exact_age, ex = final_tail$ex),
      data.table(version = "Benchmark ex-space", exact_age = ex_tail$exact_age, ex = ex_tail$ex),
      fill = TRUE
    )
    delta_dt <- copy(curve_dt)
    setorder(delta_dt, version, exact_age)
    delta_dt[, delta := c(NA_real_, diff(ex)), by = version]
    curv_dt <- copy(delta_dt[!is.na(delta)])
    curv_dt[, second_diff := c(NA_real_, diff(delta)), by = version]

    curve_fp <- file.path(plot_dir, paste0("terminal_curve_", sid, ".png"))
    delta_fp <- file.path(plot_dir, paste0("terminal_delta_", sid, ".png"))
    curv_fp <- file.path(plot_dir, paste0("terminal_curvature_", sid, ".png"))

    ggsave(curve_fp, ggplot(curve_dt, aes(exact_age, ex, color = version, linetype = version)) +
      geom_line(linewidth = 1) +
      geom_point(data = abr[abs(age_start - round(age_start)) < 1e-8 & standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value, .(exact_age = as.integer(round(age_start)), ex)], aes(exact_age, ex), inherit.aes = FALSE, color = pal[[z$sex_source_value]], shape = 21, fill = "white", stroke = 0.8, size = 2.2) +
      scale_color_manual(values = c("Contractual final" = pal[[z$sex_source_value]], "Benchmark ex-space" = "#7B8794")) +
      scale_linetype_manual(values = c("Contractual final" = "solid", "Benchmark ex-space" = "22")) +
      scale_x_continuous(breaks = seq(75, 125, 5)) +
      labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": curva terminal"), subtitle = "La salida final usa una ley de mortalidad avanzada; el benchmark ex-space queda como comparador reproducible.", x = "Edad exacta / soporte interno", y = "e(x)", color = "Serie", linetype = "Serie") +
      tportal(), width = 10.6, height = 5.8, dpi = 180, bg = "white")

    ggsave(delta_fp, ggplot(delta_dt[exact_age >= 80 & !is.na(delta)], aes(exact_age, delta, color = version, linetype = version)) +
      geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) +
      geom_line(linewidth = 1) +
      scale_color_manual(values = c("Contractual final" = pal[[z$sex_source_value]], "Benchmark ex-space" = "#7B8794")) +
      scale_linetype_manual(values = c("Contractual final" = "solid", "Benchmark ex-space" = "22")) +
      scale_x_continuous(breaks = seq(80, 125, 5)) +
      labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": delta anual en cola"), subtitle = "Despues de 85 el delta se interpreta como efecto del cierre, no como observacion directa de la fuente.", x = "Edad exacta / soporte interno", y = "delta de e(x)", color = "Serie", linetype = "Serie") +
      tportal(), width = 10.6, height = 5.2, dpi = 180, bg = "white")

    ggsave(curv_fp, ggplot(curv_dt[exact_age >= 81 & !is.na(second_diff)], aes(exact_age, second_diff, color = version, linetype = version)) +
      geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) +
      geom_line(linewidth = 1) +
      scale_color_manual(values = c("Contractual final" = pal[[z$sex_source_value]], "Benchmark ex-space" = "#7B8794")) +
      scale_linetype_manual(values = c("Contractual final" = "solid", "Benchmark ex-space" = "22")) +
      scale_x_continuous(breaks = seq(80, 125, 5)) +
      labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": curvatura de cola"), subtitle = "Segunda diferencia discreta para detectar quiebres y cambios de forma del cierre.", x = "Edad exacta / soporte interno", y = "segunda diferencia", color = "Serie", linetype = "Serie") +
      tportal(), width = 10.6, height = 5.2, dpi = 180, bg = "white")

    manifest[[i]] <- data.table(
      standard_source = z$standard_source,
      standard_version = z$standard_version,
      sex_id = z$sex_id,
      sex_source_value = z$sex_source_value,
      curve_png = rel(curve_fp),
      delta_png = rel(delta_fp),
      curvature_png = rel(curv_fp)
    )

    sel_final <- selected_methods[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value & family == "law_based"]
    sel_ex <- selected_methods[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value & family == "ex_space"]
    term_one <- terminal_summary[standard_source == z$standard_source & standard_version == z$standard_version & sex_id == z$sex_id & sex_source_value == z$sex_source_value]

    sections <- c(sections, paste0(
      "<section class=\"section-card\"><h2>", esc(z$standard_source), " / ", esc(z$standard_version), " / ", esc(z$sex_source_value), "</h2>",
      "<div class=\"chips\"><span class=\"chip\"><strong>Metodo final</strong><span>", esc(sel_final$selected_method[1]), "</span></span>",
      "<span class=\"chip\"><strong>Benchmark ex-space</strong><span>", esc(sel_ex$selected_method[1]), "</span></span>",
      "<span class=\"chip\"><strong>ex(110+)</strong><span>", format(round(term_one$ex_110plus[1], 3), nsmall = 3), "</span></span>",
      "<span class=\"chip\"><strong>Soporte interno</strong><span>hasta 125</span></span></div>",
      "<p class=\"muted\">La fuente abridged aporta 85+ como intervalo abierto. El contractual final exporta 0:109 y 110+, y deriva ex(110+) desde una cola interna modelada hasta 125.</p>",
      "<img class=\"plot\" src=\"", rel(curve_fp), "\" alt=\"Curva terminal\">",
      "<img class=\"plot\" src=\"", rel(delta_fp), "\" alt=\"Delta terminal\" style=\"margin-top:12px\">",
      "<img class=\"plot\" src=\"", rel(curv_fp), "\" alt=\"Curvatura terminal\" style=\"margin-top:12px\">",
      "</section>"
    ))
  }

  manifest_dt <- rbindlist(manifest, fill = TRUE)
  fwrite(manifest_dt, file.path(download_dir, "terminal_plot_manifest.csv"))
  fwrite(selected_methods, file.path(download_dir, "single_age_tail_selected_methods.csv"))
  fwrite(terminal_summary, file.path(download_dir, "qc_standard_life_table_terminal_summary.csv"))

  html <- c(
    "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Cola terminal y 110+</title><link rel=\"stylesheet\" href=\"assets/portal.css\"></head><body>",
    "<header class=\"site-header\"><div class=\"eyebrow\">tabla-vida-estandar / modulo terminal</div><h1>Cola terminal y 110+</h1>",
    "<p class=\"lede\">Modulo para revisar el comportamiento post-85, el soporte interno hasta 125 y la comparacion entre el metodo final y el benchmark ex-space.</p>",
    "<div class=\"nav-pills\"><a class=\"btn\" href=\"index.html\">Inicio</a><a class=\"btn\" href=\"qc_tecnico.html\">QC tecnico</a><a class=\"btn\" href=\"coherencia_tabla_estandar.html\">Coherencia</a><a class=\"btn primary\" href=\"cola_terminal_110plus.html\">Cola terminal</a></div></header>",
    "<main><section class=\"section-card\"><h2>Lectura correcta del delta</h2><p class=\"muted\">Despues de 85 la forma ya no es observacion directa de la fuente abridged. El delta y la curvatura se leen como evidencia del metodo de cierre.</p></section>",
    "<section class=\"section-card\"><h2>Metodos seleccionados</h2><div class=\"table-wrap\"><table><tr><th>source</th><th>version</th><th>sexo</th><th>familia</th><th>metodo</th><th>ex_110plus</th><th>jump_84_85</th><th>rebound_ratio_95</th></tr>",
    paste(apply(selected_methods, 1, function(r) paste0("<tr><td>", esc(r[["standard_source"]]), "</td><td>", esc(r[["standard_version"]]), "</td><td>", esc(r[["sex_source_value"]]), "</td><td>", esc(r[["family"]]), "</td><td>", esc(r[["selected_method"]]), "</td><td>", format(round(as.numeric(r[["ex_110plus"]]), 3), nsmall = 3), "</td><td>", format(round(as.numeric(r[["jump_84_85"]]), 3), nsmall = 3), "</td><td>", format(round(as.numeric(r[["rebound_ratio_95"]]), 3), nsmall = 3), "</td></tr>")), collapse = ""),
    "</table></div></section>",
    sections,
    "<section class=\"section-card\"><h2>Descargas</h2><div class=\"page-actions\"><a class=\"btn\" href=\"downloads/single_age_tail_selected_methods.csv\">Metodos seleccionados</a><a class=\"btn\" href=\"downloads/terminal_plot_manifest.csv\">Manifest de graficos</a><a class=\"btn\" href=\"downloads/qc_standard_life_table_terminal_summary.csv\">Resumen terminal</a></div></section>",
    "</main></body></html>"
  )
  writeLines(html, file.path(portal_dir, page_name), useBytes = TRUE)

  for (fp in c(file.path(portal_dir, page_name), file.path(download_dir, "terminal_plot_manifest.csv"), file.path(download_dir, "single_age_tail_selected_methods.csv"), file.path(download_dir, "qc_standard_life_table_terminal_summary.csv"), file.path(plot_dir, manifest_dt$curve_png), file.path(plot_dir, manifest_dt$delta_png), file.path(plot_dir, manifest_dt$curvature_png))) {
    if (file.exists(fp)) register_artifact("standard_life_table", "standard_life_table_terminal_module", "standard_life_table_terminal_module_v1", run_id, if (tools::file_ext(fp) %in% c("html", "pdf")) "report" else "qc", fp, notes = "Modulo terminal de tabla de vida estandar.")
  }

  register_run_finish(run_id, "success", "Modulo terminal generado")
  message("Modulo terminal generado: ", normalizePath(file.path(portal_dir, page_name), winslash = "/", mustWork = FALSE))
}, error = fail_run)
