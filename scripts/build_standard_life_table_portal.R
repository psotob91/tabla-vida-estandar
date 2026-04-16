#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(here)
  library(grid)
  library(jsonlite)
  library(plotly)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))

run_id <- paste0("standard_life_table_portal_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id, "standard_life_table", "standard_life_table_portal_v4")

fail_run <- function(e) {
  register_run_finish(run_id, "failed", conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  portal_dir <- file.path(p$REPORTS_DIR, "qc_standard_life_table")
  asset_dir <- file.path(portal_dir, "assets")
  plotly_dir <- file.path(asset_dir, "plotlyjs")
  plot_dir <- file.path(portal_dir, "plots")
  download_dir <- file.path(portal_dir, "downloads")
  tomo_dir <- file.path(portal_dir, "tomos")
  invisible(lapply(list(asset_dir, plot_dir, download_dir, tomo_dir, plotly_dir), dir.create, recursive = TRUE, showWarnings = FALSE))
  plotly_lib_src <- system.file("htmlwidgets", "lib", "plotlyjs", package = "plotly")
  if (dir.exists(plotly_lib_src)) {
    file.copy(list.files(plotly_lib_src, full.names = TRUE), plotly_dir, recursive = TRUE, overwrite = TRUE)
  } else {
    stop("No se encontro la libreria local de plotly.js dentro del paquete plotly.")
  }

  abr <- fread(file.path(p$FINAL_DIR, "life_table_standard_reference_abridged.csv"))
  sa <- fread(file.path(p$FINAL_DIR, "life_table_standard_reference_single_age.csv"))
  qc_summary <- fread(file.path(p$QC_DIR, "qc_standard_life_table_summary.csv"))
  knot_summary <- fread(file.path(p$QC_DIR, "qc_standard_life_table_knot_comparison_summary.csv"))
  terminal_summary <- fread(file.path(p$QC_DIR, "qc_standard_life_table_terminal_summary.csv"))
  selected_methods <- fread(file.path(p$QC_DIR, "single_age_tail_selected_methods.csv"))
  support_ex <- fread(file.path(p$QC_DIR, "single_age_tail_support_ex_space_to_125.csv"))
  compare_tail <- fread(file.path(p$QC_DIR, "single_age_tail_final_vs_exspace.csv"))
  method_detail <- fread(file.path(p$QC_DIR, "single_age_tail_method_detail.csv"))
  method_summary <- fread(file.path(p$QC_DIR, "single_age_tail_method_summary.csv"))

  abr_cols <- ncol(abr)
  sa_cols <- ncol(sa)
  abr[, exact_age_candidate := ifelse(abs(age_start - round(age_start)) < 1e-9, as.integer(round(age_start)), NA_integer_)]
  abr_int <- abr[!is.na(exact_age_candidate)]

  repair_mojibake <- function(x) {
    x <- as.character(x)
    bad <- grepl("Ã.|Â.|â.|ð", x)
    if (any(bad, na.rm = TRUE)) {
      repaired <- iconv(x[bad], from = "latin1", to = "UTF-8")
      ok <- !is.na(repaired)
      idx <- which(bad)
      x[idx[ok]] <- repaired[ok]
    }
    x
  }
  esc <- function(x) {
    x <- repair_mojibake(x)
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub('"', "&quot;", x, fixed = TRUE)
  }
  slug <- function(x) {
    x <- tolower(iconv(as.character(x), to = "ASCII//TRANSLIT", sub = ""))
    x <- gsub("[^a-z0-9]+", "-", x)
    gsub("(^-|-$)", "", x)
  }
  rel <- function(path) sub(paste0("^", normalizePath(portal_dir, winslash = "/", mustWork = FALSE), "/"), "", normalizePath(path, winslash = "/", mustWork = FALSE))
  wtxt <- function(path, x) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(enc2utf8(repair_mojibake(x)), path, useBytes = TRUE)
  }
  fnum <- function(x, d = 2) ifelse(is.na(x), "", format(round(x, d), nsmall = d, trim = TRUE, scientific = FALSE))
  fint <- function(x) ifelse(is.na(x), "", format(as.integer(round(x)), trim = TRUE, scientific = FALSE))
  fbool <- function(x) ifelse(is.na(x), "", ifelse(isTRUE(x) | x %in% c("TRUE", "true", "Si", "SI"), "Si", "No"))
  pal <- c(Female = "#C73E88", Male = "#1D4ED8", Persons = "#0F766E")
  final_curve_label <- "Método final contractual"
  benchmark_curve_label <- "Comparador en espacio de e(x)"
  abridged_points_label <- "Puntos observados abridged"
  cmp_pal <- c("Método final contractual" = "#0F766E", "Comparador en espacio de e(x)" = "#7B8794")
  glossary <- rbindlist(list(
    data.table(term_key = "ex", label = "e(x)", technical_name = "ex", category = "bioestadística", definition = "Esperanza de vida restante a la edad exacta x, expresada en años.", formula = "e(x)", ok_pattern = "Debe mantenerse no negativa y descender de forma plausible con la edad.", review_pattern = "Valores negativos o cambios abruptos sin explicación exigen revisar la expansión.", annex_anchor = "sec-metrica-ex"),
    data.table(term_key = "delta_ex", label = "Delta anual de e(x)", technical_name = "delta_ex", category = "bioestadística", definition = "Cambio anual de e(x) entre dos edades consecutivas.", formula = "Delta e(x)=e(x+1)-e(x)", ok_pattern = "Antes de 85 conviene ver continuidad entre puntos observados; después de 85 debe sostener un cierre terminal plausible.", review_pattern = "Rebotes bruscos hacia 0 o saltos grandes sugieren un cierre poco natural.", annex_anchor = "sec-delta-curvatura"),
    data.table(term_key = "second_diff", label = "Curvatura discreta", technical_name = "second_diff", category = "bioestadística", definition = "Segunda diferencia discreta del delta; resume cambios bruscos en la pendiente.", formula = "Delta^2 e(x)=Delta e(x+1)-Delta e(x)", ok_pattern = "Cambios moderados alrededor de 0 son compatibles con una cola suave.", review_pattern = "Picos o alternancias fuertes pueden delatar quiebres o tramos excesivamente rectificados.", annex_anchor = "sec-delta-curvatura"),
    data.table(term_key = "knot", label = "Punto observado abridged (knot)", technical_name = "knot", category = "bioestadística", definition = "Edad observada en la tabla abridged que la expansión a edad simple debe reproducir exactamente cuando existe como edad entera.", formula = "e_abridged(x_k)=e_final(x_k)", ok_pattern = "Lo esperable es conservar todos los knots sin error.", review_pattern = "Si faltan knots o aparece error, la expansión está modificando información observada de la fuente.", annex_anchor = "sec-knots"),
    data.table(term_key = "ex_negative", label = "e(x) negativa", technical_name = "ex_negative", category = "qc", definition = "Control que detecta filas con esperanza de vida menor que cero.", formula = "e(x)<0", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Cualquier fila distinta de 0 indica una incoherencia sustantiva.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "bad_age_order", label = "Orden incorrecto de edades", technical_name = "bad_age_order", category = "qc", definition = "Control que detecta edades fuera de secuencia dentro de un estrato.", formula = "edad(i+1)<edad(i)", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Si aparece, la tabla puede estar desordenada o mal transformada.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "bad_age_width", label = "Ancho de edad inesperado", technical_name = "bad_age_width", category = "qc", definition = "Control del ancho de intervalo esperado para la tabla correspondiente.", formula = "age_end-age_start", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Valores fuera del ancho esperado sugieren una estructura de edades mal definida.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "duplicate_pk", label = "Llave duplicada", technical_name = "duplicate_pk", category = "qc", definition = "Control de unicidad de la llave lógica de la tabla.", formula = "N>1 por llave primaria", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Duplicados implican ambigüedad y rompen el contrato.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "terminal_ex_nonpositive", label = "e(110+) no positiva", technical_name = "terminal_ex_nonpositive", category = "qc", definition = "Control que verifica que el último intervalo abierto conserve una esperanza de vida positiva.", formula = "e(110+)<=0", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Si falla, el cierre terminal contradice el contrato actual.", annex_anchor = "sec-tramo-terminal"),
    data.table(term_key = "terminal_terminal_value_incoherent", label = "Valor terminal incoherente", technical_name = "terminal_terminal_value_incoherent", category = "qc", definition = "Control de coherencia entre el valor exportado en 110+ y la cola interna de soporte.", formula = "e(110+) exportado frente a soporte 110:125", ok_pattern = "Estado OK y n_rows=0.", review_pattern = "Si falla, el último intervalo abierto no queda alineado con la cola interna.", annex_anchor = "sec-tramo-terminal"),
    data.table(term_key = "max_abs_diff", label = "Error máximo en puntos observados", technical_name = "max_abs_diff", category = "metric", definition = "Mayor diferencia absoluta entre el valor abridged y el valor final en edades knot.", formula = "max |e_abridged-e_final|", ok_pattern = "El valor ideal es 0.", review_pattern = "Valores mayores a 0 indican que la expansión no preservó exactamente la fuente.", annex_anchor = "sec-knots"),
    data.table(term_key = "mean_abs_diff", label = "Error medio en puntos observados", technical_name = "mean_abs_diff", category = "metric", definition = "Promedio del error absoluto en las edades knot.", formula = "mean |e_abridged-e_final|", ok_pattern = "Debe ser 0 si la preservación fue exacta.", review_pattern = "Si aumenta, la expansión se aleja de la fuente en forma sistemática.", annex_anchor = "sec-knots"),
    data.table(term_key = "n_missing_single_age", label = "Puntos observados faltantes", technical_name = "n_missing_single_age", category = "metric", definition = "Cantidad de knots abridged que no encuentran equivalente en la tabla final.", formula = "conteo de knots sin correspondencia", ok_pattern = "El valor esperable es 0.", review_pattern = "Valores positivos indican pérdida directa de información observada.", annex_anchor = "sec-knots"),
    data.table(term_key = "jump_84_85", label = "Quiebre 84-85", technical_name = "jump_84_85", category = "metric", definition = "Magnitud del cambio de pendiente al entrar al tramo abierto 85+.", formula = "|Delta e(85)-Delta e(84)|", ok_pattern = "Valores pequeños sugieren una transición suave entre el tramo observado y la cola modelada.", review_pattern = "Valores grandes sugieren un quiebre visual o metodológico.", annex_anchor = "sec-metricas-terminales"),
    data.table(term_key = "rebound_ratio_95", label = "Rebote del delta hacia 95", technical_name = "rebound_ratio_95", category = "metric", definition = "Resume qué tan rápido el delta se acerca a 0 al avanzar por la cola terminal.", formula = "razón de acercamiento del delta entre 85 y 95", ok_pattern = "Un rebote gradual suele ser más plausible.", review_pattern = "Un rebote demasiado rápido puede indicar una cola excesivamente forzada.", annex_anchor = "sec-metricas-terminales"),
    data.table(term_key = "score", label = "Puntaje comparativo", technical_name = "score", category = "metric", definition = "Indicador sintético utilizado solo para ordenar candidatos de cierre dentro del comparador metodológico.", formula = "función resumen interna", ok_pattern = "Sirve para comparar métodos dentro del mismo estrato, no como medida absoluta.", review_pattern = "No debe interpretarse aisladamente sin mirar quiebre, rebote y e(110+).", annex_anchor = "sec-seleccion-metodo"),
    data.table(term_key = "law_based", label = "Familia basada en ley de mortalidad", technical_name = "law_based", category = "method", definition = "Familia de métodos que construye la cola avanzada mediante una ley de mortalidad y luego deriva e(x).", formula = NA_character_, ok_pattern = "Corresponde a la familia contractual final del proyecto.", review_pattern = "Debe evaluarse con delta, curvatura y e(110+) igual que cualquier otro método.", annex_anchor = "sec-familia-law-based"),
    data.table(term_key = "ex_space", label = "Comparador en espacio de e(x)", technical_name = "ex_space", category = "method", definition = "Familia comparadora que modela directamente la forma de e(x) sin convertirse en contrato final.", formula = NA_character_, ok_pattern = "Funciona como comparador reproducible del cierre terminal.", review_pattern = "No debe confundirse con la salida contractual final.", annex_anchor = "sec-comparador-ex-space"),
    data.table(term_key = "kannisto", label = "Kannisto", technical_name = "kannisto", category = "method", definition = "Ley de mortalidad avanzada utilizada para suavizar la cola terminal.", formula = NA_character_, ok_pattern = "Debe producir una cola monótona y plausible cuando el estrato lo permite.", review_pattern = "Si deja quiebres o rebotes anormales, puede no ser la mejor opción en ese estrato.", annex_anchor = "sec-familia-law-based"),
    data.table(term_key = "coale_kisker_like", label = "Coale-Kisker", technical_name = "coale_kisker_like", category = "method", definition = "Familia alternativa de cierre terminal utilizada como comparador dentro de los métodos basados en ley de mortalidad.", formula = NA_character_, ok_pattern = "Puede mejorar continuidad local en algunos estratos.", review_pattern = "Debe auditarse con delta, curvatura y e(110+).", annex_anchor = "sec-familia-law-based"),
    data.table(term_key = "anchor_bridge", label = "Puente de anclaje", technical_name = "anchor_bridge", category = "method", definition = "Ajuste que fuerza una transición más suave entre el último punto observado y la cola modelada.", formula = NA_character_, ok_pattern = "Ayuda a reducir quiebres locales.", review_pattern = "Si suaviza demasiado, puede aplanar la cola en exceso.", annex_anchor = "sec-familia-law-based"),
    data.table(term_key = "blend95", label = "Mezcla progresiva hacia 95", technical_name = "blend95", category = "method", definition = "Variante que suaviza la transición de la cola mediante una mezcla progresiva hasta edades cercanas a 95.", formula = NA_character_, ok_pattern = "Puede reducir quiebres locales.", review_pattern = "Puede producir deltas demasiado planos si se fuerza en exceso.", annex_anchor = "sec-familia-law-based"),
    data.table(term_key = "baseline_repo", label = "Referencia histórica del repositorio", technical_name = "baseline_repo", category = "method", definition = "Método heredado del repositorio utilizado solo como referencia histórica del comparador.", formula = NA_character_, ok_pattern = "Se interpreta como referencia de comparación.", review_pattern = "No debe leerse como mejor método por defecto.", annex_anchor = "sec-seleccion-metodo"),
    data.table(term_key = "polynomial_delta", label = "Ajuste polinómico del delta", technical_name = "polynomial_delta", category = "method", definition = "Comparador que suaviza la cola trabajando sobre el delta anual en espacio e(x).", formula = NA_character_, ok_pattern = "Puede servir como comparador de forma.", review_pattern = "Si empuja e(110+) a 0 o rectifica demasiado la cola, se descarta como salida contractual.", annex_anchor = "sec-comparador-ex-space"),
    data.table(term_key = "benchmark", label = "Comparador metodológico", technical_name = "benchmark", category = "method", definition = "Comparación reproducible utilizada para evaluar métodos alternativos sin convertirlos en contrato final.", formula = NA_character_, ok_pattern = "Debe usarse para contrastar candidatos dentro del mismo problema.", review_pattern = "No debe interpretarse como un segundo contrato.", annex_anchor = "sec-seleccion-metodo"),
    data.table(term_key = "fingerprint", label = "Huella estructural del output", technical_name = "fingerprint", category = "qc", definition = "Resumen reproducible de filas, columnas, llave y variable de edad de cada salida contractual.", formula = NA_character_, ok_pattern = "Conteos, columnas y granularidad estables entre corridas comparables.", review_pattern = "Cambios inesperados suelen indicar una alteración real del contrato.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "pipeline", label = "Flujo reproducible del proyecto", technical_name = "pipeline", category = "source", definition = "Secuencia ordenada de scripts que construye insumos, salidas finales, controles, reportes y portal.", formula = NA_character_, ok_pattern = "Debe ejecutarse de forma determinista desde los entrypoints oficiales.", review_pattern = "Pasos manuales fuera de ese flujo rompen reproducibilidad.", annex_anchor = "sec-flujo-reproducible"),
    data.table(term_key = "baseline", label = "Referencia baseline", technical_name = "baseline", category = "source", definition = "Instantánea de referencia utilizada para comparar estabilidad contractual antes y después de cambios.", formula = NA_character_, ok_pattern = "La comparación debe preservar estructura, tipos y granularidad.", review_pattern = "Diferencias no explicadas indican un incidente de compatibilidad.", annex_anchor = "sec-qc-informatico"),
    data.table(term_key = "age_end_120", label = "age_end = 120 en la fuente", technical_name = "age_end = 120", category = "source", definition = "Código usado por la fuente para representar el intervalo abierto 85+.", formula = NA_character_, ok_pattern = "Debe leerse como codificación del abierto.", review_pattern = "No debe interpretarse como evidencia de un intervalo cerrado 85-120 observado.", annex_anchor = "sec-fuente-abierta"),
    data.table(term_key = "support_125", label = "Soporte interno hasta 125", technical_name = "support_age_max = 125", category = "source", definition = "Horizonte interno de cálculo utilizado para construir una cola coherente y derivar e(110+).", formula = NA_character_, ok_pattern = "Es un soporte de modelado, no una edad observada en la fuente.", review_pattern = "No contradice age_end = 120 porque cumplen funciones distintas.", annex_anchor = "sec-fuente-abierta"),
    data.table(term_key = "terminal_open_interval", label = "110+ como grupo abierto final", technical_name = "terminal open interval", category = "source", definition = "Último intervalo exportado del contrato final.", formula = "0:109 y 110+", ok_pattern = "Debe quedar abierto y con e(110+) positiva.", review_pattern = "Si se fuerza a 0 o se cierra implícitamente, se rompe la semántica contractual.", annex_anchor = "sec-tramo-terminal"),
    data.table(term_key = "terminal_policy", label = "Política terminal", technical_name = "terminal_policy_current", category = "source", definition = "Regla con la que el proyecto representa el intervalo abierto final y su esperanza de vida asociada.", formula = NA_character_, ok_pattern = "Debe ser consistente con un 110+ abierto y con la cola interna hasta 125.", review_pattern = "Inconsistencias entre política, valor terminal y soporte interno requieren revisiones.", annex_anchor = "sec-tramo-terminal"),
    data.table(term_key = "terminal_closure", label = "Cierre terminal", technical_name = "terminal closure", category = "source", definition = "Conjunto de decisiones metodológicas usadas para completar la forma post-85, donde la fuente ya no observa edades simples.", formula = NA_character_, ok_pattern = "Debe ser coherente con la fuente, con e(110+) positiva y con una cola visualmente plausible.", review_pattern = "Quiebres dominantes o rectificaciones excesivas indican un cierre terminal poco convincente.", annex_anchor = "sec-tramo-terminal")
  ), fill = TRUE)
  gloss_index <- split(glossary, glossary$term_key)
  gloss_lookup <- function(key, field) {
    if (!key %in% names(gloss_index)) return("")
    value <- gloss_index[[key]][[field]][1]
    ifelse(is.na(value), "", as.character(value))
  }
  tooltip_label <- function(key, label = NULL) {
    label <- if (is.null(label)) gloss_lookup(key, "label") else label
    if (!nzchar(label)) label <- key
    if (!key %in% names(gloss_index)) return(esc(label))
    tip_bits <- c(
      paste0("<strong>", esc(gloss_lookup(key, "label")), "</strong>"),
      paste0("<span class=\"tooltip-tech\">Nombre técnico: ", esc(gloss_lookup(key, "technical_name")), "</span>"),
      paste0("<span>", esc(gloss_lookup(key, "definition")), "</span>")
    )
    if (nzchar(gloss_lookup(key, "formula"))) tip_bits <- c(tip_bits, paste0("<span class=\"tooltip-formula\">", esc(gloss_lookup(key, "formula")), "</span>"))
    if (nzchar(gloss_lookup(key, "ok_pattern"))) tip_bits <- c(tip_bits, paste0("<span><strong>Patrón esperado:</strong> ", esc(gloss_lookup(key, "ok_pattern")), "</span>"))
    if (nzchar(gloss_lookup(key, "review_pattern"))) tip_bits <- c(tip_bits, paste0("<span><strong>Señal de alerta:</strong> ", esc(gloss_lookup(key, "review_pattern")), "</span>"))
    if (nzchar(gloss_lookup(key, "annex_anchor"))) {
      tip_bits <- c(tip_bits, paste0("<a class=\"tooltip-link\" href=\"../auditoria_tabla_vida_estandar.html#", esc(gloss_lookup(key, "annex_anchor")), "\">Ver anexo metodológico</a>"))
    }
    paste0("<span class=\"info-term\" tabindex=\"0\"><span class=\"term-text\">", esc(label), "</span><span class=\"info-icon\" aria-hidden=\"true\">i</span><span class=\"tooltip-box\">", paste(tip_bits, collapse = ""), "</span></span>")
  }
  human_check <- c(
    ex_negative = "e(x) negativa",
    bad_age_order = "Orden incorrecto de edades",
    bad_age_width = "Ancho de edad inesperado",
    units_not_years = "Unidades distintas de años",
    ex_not_monotone_expected = "No monótona cuando se esperaba monotonicidad",
    duplicate_pk = "Llave duplicada",
    open_interval_count_bad = "Conteo incorrecto de intervalos abiertos",
    open_interval_bad_age = "Intervalo abierto en edad equivocada",
    terminal_label_bad = "Etiqueta terminal incorrecta",
    age_start_not_exact_age = "age_start no coincide con exact_age",
    age_end_not_plus_one = "age_end no sigue la convención esperada",
    open_age_end_bad = "age_end del abierto inconsistente",
    terminal_ex_nonpositive = "e(110+) no positiva",
    knot_preservation = "Preservación de puntos observados",
    terminal_open_interval_count_bad = "Conteo terminal abierto incorrecto",
    terminal_terminal_structure_bad = "Estructura terminal incoherente",
    terminal_source_open_interval_missing = "La fuente no marca 85+ como abierto",
    terminal_source_open_age_not_before_terminal = "La fuente abre después del inicio del grupo exportado",
    terminal_monotone_expected_bad = "Cola no monótona cuando se esperaba monotonicidad",
    terminal_terminal_open_ex_nonpositive = "e(110+) terminal no positiva",
    terminal_terminal_policy_mismatch = "Politica terminal inconsistente",
    terminal_terminal_value_incoherent = "Valor terminal incoherente"
  )
  check_to_key <- c(
    ex_negative = "ex_negative",
    bad_age_order = "bad_age_order",
    bad_age_width = "bad_age_width",
    duplicate_pk = "duplicate_pk",
    terminal_ex_nonpositive = "terminal_ex_nonpositive",
    terminal_terminal_value_incoherent = "terminal_terminal_value_incoherent",
    knot_preservation = "knot"
  )
  human_check_html <- function(x) {
    label <- ifelse(x %in% names(human_check), human_check[x], x)
    key <- ifelse(x %in% names(check_to_key), check_to_key[x], "")
    ifelse(nzchar(key), tooltip_label(key, label), esc(label))
  }
  human_family <- function(x) fifelse(x == "law_based", "Ley de mortalidad", fifelse(x == "ex_space", "Comparador en e(x)", x))
  human_family_html <- function(x) ifelse(x == "law_based", tooltip_label("law_based", "Ley de mortalidad"), ifelse(x == "ex_space", tooltip_label("ex_space", "Comparador en e(x)"), esc(x)))
  human_method <- function(x) {
    out <- gsub("coale_kisker_like", "Coale-Kisker", x, fixed = TRUE)
    out <- gsub("kannisto", "Kannisto", out, fixed = TRUE)
    out <- gsub("_anchor_bridge", " con puente de anclaje", out, fixed = TRUE)
    out <- gsub("_blend95", " con mezcla hacia 95", out, fixed = TRUE)
    out <- gsub("baseline_repo", "Cierre histórico del repo", out, fixed = TRUE)
    out <- gsub("polynomial_delta", "Ajuste polinómico del delta", out, fixed = TRUE)
    out
  }
  method_key_from_name <- function(x) {
    fifelse(grepl("kannisto", x, fixed = TRUE), "kannisto",
      fifelse(grepl("coale_kisker_like", x, fixed = TRUE), "coale_kisker_like",
        fifelse(grepl("baseline_repo", x, fixed = TRUE), "baseline_repo",
          fifelse(grepl("polynomial_delta", x, fixed = TRUE), "polynomial_delta", ""))))
  }
  human_method_html <- function(x) {
    key <- method_key_from_name(x)
    label <- human_method(x)
    ifelse(nzchar(key), tooltip_label(key, label), esc(label))
  }
  interpretation_box <- function(ok_text, review_text, note_text = NULL) {
    extra <- if (!is.null(note_text)) paste0("<p><strong>Nota:</strong> ", esc(note_text), "</p>") else ""
    paste0("<div class=\"interpret-box\"><h4>Interpretación</h4><p><strong>Patrón esperado:</strong> ", esc(ok_text), "</p><p><strong>Señal de alerta:</strong> ", esc(review_text), "</p>", extra, "</div>")
  }
  table_note <- function(x) paste0("<p class=\"table-note\">", esc(x), "</p>")
  tportal <- function() theme_minimal(base_size = 11) + theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "#E6ECF2"),
    plot.title = element_text(face = "bold", size = 13, color = "#102A43"),
    plot.subtitle = element_text(size = 9.5, color = "#486581"),
    axis.text = element_text(color = "#334E68"),
    axis.title = element_text(color = "#102A43"),
    legend.position = "bottom",
    legend.title = element_text(face = "bold")
  )
  splot <- function(plot, path, w = 10.4, h = 5.7) ggsave(path, plot = plot, width = w, height = h, dpi = 170, bg = "white")
  table_html <- function(dt, max_rows = 12, status_cols = character(), digits = 2, wrapper_class = "table-wrap", table_class = "summary-table", html_cols = character(), header_labels = NULL) {
    if (!nrow(dt)) return("<p class=\"muted\">Sin registros.</p>")
    x <- copy(dt)
    if (nrow(x) > max_rows) x <- x[1:max_rows]
    num_cols <- names(x)[vapply(x, function(z) is.numeric(z) || is.integer(z), logical(1))]
    for (nm in names(x)) x[[nm]] <- if (nm %in% num_cols) {
      if (is.integer(dt[[nm]]) || all(abs(dt[[nm]] - round(dt[[nm]])) < 1e-9, na.rm = TRUE)) fint(x[[nm]]) else fnum(x[[nm]], digits)
    } else as.character(x[[nm]])
    hdr_cells <- vapply(names(x), function(nm) {
      lab <- if (!is.null(header_labels) && nm %in% names(header_labels)) header_labels[[nm]] else esc(nm)
      paste0("<th", ifelse(nm %in% num_cols, " class=\"num\"", ""), ">", lab, "</th>")
    }, character(1))
    hdr <- paste0("<tr>", paste0(hdr_cells, collapse = ""), "</tr>")
    rows <- apply(x, 1, function(r) {
      tds <- mapply(function(v, nm) {
        body <- if (nm %in% status_cols) {
          paste0("<span class=\"badge ", ifelse(toupper(v) == "OK", "ok", "alert"), "\">", esc(v), "</span>")
        } else if (nm %in% html_cols) {
          as.character(v)
        } else esc(v)
        paste0("<td", ifelse(nm %in% num_cols, " class=\"num\"", ""), ">", body, "</td>")
      }, r, names(x), USE.NAMES = FALSE)
      paste0("<tr>", paste0(tds, collapse = ""), "</tr>")
    })
    paste0("<div class=\"", wrapper_class, "\"><table class=\"", table_class, "\">", hdr, paste(rows, collapse = "\n"), "</table></div>", if (nrow(dt) > max_rows) paste0("<p class=\"small-note\">Se muestran ", max_rows, " filas de ", nrow(dt), ".</p>") else "")
  }
  detail_block <- function(title, body, open = FALSE) {
    paste0(
      "<details class=\"subdetails\"", if (open) " open" else "", "><summary>", esc(title), "</summary><div class=\"subdetails-body\">",
      body,
      "</div></details>"
    )
  }
  trace_line <- function(dt, x_col, y_col, name, color, dash = "solid", extra = "", mode = "lines+markers") {
    list(
      type = "scatter", mode = mode, name = name,
      x = dt[[x_col]], y = round(dt[[y_col]], 6),
      line = list(color = color, width = 2.2, dash = dash),
      marker = list(color = color, size = 6),
      hovertemplate = paste0("<b>", esc(name), "</b><br>Edad: %{x}<br>", extra, "%{y:.6f}<extra></extra>")
    )
  }
  trace_marker <- function(dt, x_col, y_col, name, color, extra = "") {
    list(
      type = "scatter", mode = "markers", name = name,
      x = dt[[x_col]], y = round(dt[[y_col]], 6),
      marker = list(color = color, size = 8, symbol = "circle-open", line = list(width = 1.3, color = color)),
      hovertemplate = paste0("<b>", esc(name), "</b><br>Edad: %{x}<br>", extra, "%{y:.6f}<extra></extra>")
    )
  }

  delta <- copy(sa)
  setorder(delta, standard_source, standard_version, sex_source_value, exact_age)
  delta[, delta_ex := c(NA_real_, diff(ex)), by = .(standard_source, standard_version, sex_source_value)]
  delta[, abs_delta_ex := abs(delta_ex)]
  delta[, age_band := fifelse(exact_age <= 4, "0-4", fifelse(exact_age <= 14, "5-14", fifelse(exact_age <= 29, "15-29", fifelse(exact_age <= 49, "30-49", fifelse(exact_age <= 69, "50-69", "70+")))))]

  knot <- merge(
    abr_int[, .(standard_source, standard_version, sex_id, sex_source_value, exact_age = exact_age_candidate, abridged_ex = ex)],
    sa[, .(standard_source, standard_version, sex_id, sex_source_value, exact_age, single_age_ex = ex)],
    by = c("standard_source", "standard_version", "sex_id", "sex_source_value", "exact_age"),
    all.x = TRUE
  )
  knot[, abs_diff_ex := abs(abridged_ex - single_age_ex)]

  meta <- sa[, .(n_sex = uniqueN(sex_source_value), sex_values = paste(sort(unique(sex_source_value)), collapse = "|")), by = .(standard_source, standard_version)]
  selections <- rbindlist(lapply(seq_len(nrow(meta)), function(i) {
    z <- meta[i]; sexes <- strsplit(z$sex_values, "\\|")[[1]]
    if (z$n_sex > 1) rbind(
      data.table(standard_source = z$standard_source, standard_version = z$standard_version, sex_mode = "compare", sex_label = "Comparar sexos", sex_values = paste(sexes, collapse = "|"), ord = 1L),
      data.table(standard_source = z$standard_source, standard_version = z$standard_version, sex_mode = sexes, sex_label = paste0("Ver ", sexes), sex_values = sexes, ord = seq_along(sexes) + 1L)
    ) else data.table(standard_source = z$standard_source, standard_version = z$standard_version, sex_mode = sexes, sex_label = paste0("Vista disponible: ", sexes), sex_values = sexes, ord = 1L)
  }))
  setorder(selections, standard_source, standard_version, ord, sex_mode)

  portal_data <- list(coherence = list(), terminal = list(), catalog = list())
  panel_meta <- data.table()
  plot_manifest <- data.table()

  for (i in seq_len(nrow(selections))) {
    s <- selections[i]
    sex_values <- strsplit(s$sex_values, "\\|")[[1]]
    pid <- paste(slug(s$standard_source), slug(s$standard_version), slug(s$sex_mode), sep = "_")
    sa_i <- sa[standard_source == s$standard_source & standard_version == s$standard_version & sex_source_value %in% sex_values]
    abr_i <- abr_int[standard_source == s$standard_source & standard_version == s$standard_version & sex_source_value %in% sex_values]
    de_i <- delta[standard_source == s$standard_source & standard_version == s$standard_version & sex_source_value %in% sex_values]
    kn_i <- knot[standard_source == s$standard_source & standard_version == s$standard_version & sex_source_value %in% sex_values]
    e0 <- sa_i[exact_age == min(exact_age), .(sex_source_value, ex)]
    top_i <- de_i[!is.na(delta_ex)][order(-abs_delta_ex), .(sex_source_value, exact_age, age_band, ex, delta_ex, abs_delta_ex)]
    if (nrow(top_i) > 15) top_i <- top_i[1:15]

    cpath <- file.path(plot_dir, paste0("curve_", pid, ".png"))
    dpath <- file.path(plot_dir, paste0("delta_", pid, ".png"))
    kpath <- file.path(plot_dir, paste0("knots_", pid, ".png"))

    p_curve <- ggplot(sa_i, aes(exact_age, ex, color = sex_source_value, group = sex_source_value)) +
      geom_line(linewidth = if (s$sex_mode == "compare") 1 else 1.1) +
      geom_point(data = abr_i, aes(age_start, ex, color = sex_source_value), inherit.aes = FALSE, shape = 21, fill = "white", stroke = 0.8, size = 2.3) +
      scale_color_manual(values = pal[names(pal) %in% unique(sa_i$sex_source_value)], drop = FALSE) +
      scale_x_continuous(breaks = seq(0, 110, 10)) +
      labs(title = paste0("Curva e(x): ", s$standard_source, " / ", s$standard_version), subtitle = paste0(s$sex_label, ". Linea = contractual final; punto = knot abridged."), x = "Edad simple", y = "e(x) en años", color = "Sexo") + tportal()
    p_delta <- ggplot(de_i[!is.na(delta_ex)], aes(exact_age, delta_ex, color = sex_source_value, group = sex_source_value)) +
      geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) + geom_line(linewidth = 0.9) +
      geom_point(data = de_i[!is.na(delta_ex)][order(-abs_delta_ex)][1:min(.N, 6)], size = 2, show.legend = FALSE) +
      scale_color_manual(values = pal[names(pal) %in% unique(de_i$sex_source_value)], drop = FALSE) +
      scale_x_continuous(breaks = seq(0, 110, 10)) +
      labs(title = paste0("Delta anual de e(x): ", s$standard_source, " / ", s$standard_version), subtitle = paste0(s$sex_label, ". Despues de 85 la forma es modelada; el delta ayuda a revisar continuidad local."), x = "Edad simple", y = "Delta vs edad previa", color = "Sexo") + tportal()
    p_knot <- if (!nrow(kn_i) || max(kn_i$abs_diff_ex, na.rm = TRUE) == 0) {
      ggplot(data.table(x = 1, y = 1), aes(x, y)) + annotate("label", x = 1, y = 1, label = paste0("Preservacion exacta\nknots: ", nrow(kn_i), "\nmax error: 0.00"), fill = "#F0FDF4", color = "#166534", size = 6, fontface = "bold") + labs(title = paste0("Preservacion de knots: ", s$standard_source, " / ", s$standard_version), subtitle = paste0(s$sex_label, ". La expansión final conserva exactamente los knots abridged.")) + theme_void()
    } else {
      ggplot(kn_i, aes(exact_age, abs_diff_ex, color = sex_source_value, group = sex_source_value)) + geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) + geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
        scale_color_manual(values = pal[names(pal) %in% unique(kn_i$sex_source_value)], drop = FALSE) + scale_x_continuous(breaks = seq(0, 110, 10)) +
        labs(title = paste0("Diferencia en knots: ", s$standard_source, " / ", s$standard_version), subtitle = paste0(s$sex_label, ". Valores cercaños a cero indican preservacion de knots."), x = "Edad del knot", y = "|abridged - final|", color = "Sexo") + tportal()
    }
    splot(p_curve, cpath); splot(p_delta, dpath); splot(p_knot, kpath, h = 5.1)

    curve_traces <- unlist(lapply(unique(sa_i$sex_source_value), function(sx) {
      list(
        trace_line(sa_i[sex_source_value == sx], "exact_age", "ex", paste0(sx, " final"), pal[[sx]], extra = "e(x): "),
        trace_marker(abr_i[sex_source_value == sx], "age_start", "ex", paste0(sx, " knot"), pal[[sx]], extra = "e(x): ")
      )
    }), recursive = FALSE)
    delta_traces <- unlist(lapply(unique(de_i$sex_source_value), function(sx) {
      list(trace_line(de_i[sex_source_value == sx & !is.na(delta_ex)], "exact_age", "delta_ex", sx, pal[[sx]], extra = "Delta e(x): "))
    }), recursive = FALSE)
    knot_payload <- if (!nrow(kn_i) || max(kn_i$abs_diff_ex, na.rm = TRUE) == 0) {
      list(exact = TRUE, knots = nrow(kn_i), max_error = 0)
    } else {
      list(exact = FALSE, traces = unlist(lapply(unique(kn_i$sex_source_value), function(sx) {
        list(trace_line(kn_i[sex_source_value == sx], "exact_age", "abs_diff_ex", sx, pal[[sx]], extra = "|diff|: "))
      }), recursive = FALSE))
    }

    portal_data$coherence[[pid]] <- list(
      source = s$standard_source,
      version = s$standard_version,
      sex_mode = s$sex_mode,
      sex_label = s$sex_label,
      e0 = paste(paste0(e0$sex_source_value, ": ", fnum(e0$ex, 2)), collapse = " | "),
      visible_sexes = paste(sex_values, collapse = ", "),
      age_range = paste0(min(sa_i$exact_age), " a ", max(sa_i$exact_age)),
      curve = list(traces = curve_traces, layout = list(title = "Curva e(x)", xaxis = list(title = "Edad simple", dtick = 10), yaxis = list(title = "e(x) en años"), hovermode = "closest")),
      delta = list(traces = delta_traces, layout = list(title = "Delta anual", xaxis = list(title = "Edad simple", dtick = 10), yaxis = list(title = "Delta vs edad previa"), hovermode = "closest", shapes = list(list(type = "line", x0 = 0, x1 = 110, y0 = 0, y1 = 0, line = list(color = "#7B8794", dash = "dot"))))),
      knots = knot_payload,
      table_html = table_html(top_i, max_rows = 15, digits = 3)
    )

    panel_meta <- rbind(panel_meta, data.table(standard_source = s$standard_source, standard_version = s$standard_version, sex_mode = s$sex_mode, sex_label = s$sex_label, panel_id = pid, visible_sexes = paste(sex_values, collapse = ", "), age_range = paste0(min(sa_i$exact_age), "-", max(sa_i$exact_age)), e0 = paste(paste0(e0$sex_source_value, ": ", fnum(e0$ex, 2)), collapse = " | "), max_abs_delta = max(de_i$abs_delta_ex, na.rm = TRUE), max_knot_diff = max(kn_i$abs_diff_ex, na.rm = TRUE)), fill = TRUE)
    plot_manifest <- rbind(plot_manifest, data.table(standard_source = s$standard_source, standard_version = s$standard_version, sex_mode = s$sex_mode, curve_png = rel(cpath), delta_png = rel(dpath), knots_png = rel(kpath)), fill = TRUE)
  }

  catalog_manifest <- data.table()
  for (sex in sort(unique(sa$sex_source_value))) {
    x <- sa[sex_source_value == sex]
    x[, standard_label := paste(standard_source, standard_version, sep = " / ")]
    path <- file.path(plot_dir, paste0("catalog_profile_", slug(sex), ".png"))
    p_aux <- ggplot(x, aes(exact_age, ex, color = standard_label)) + geom_line(linewidth = 1) + facet_wrap(~standard_label, ncol = 1, scales = "free_y") + scale_x_continuous(breaks = seq(0, 110, 10)) + scale_color_brewer(palette = "Dark2", guide = "none") + labs(title = paste0("Comparador del catálogo por sexo: ", sex), subtitle = "Small multiples para revisar forma general y nivel de e(x).", x = "Edad simple", y = "e(x) en años") + tportal()
    splot(p_aux, path, h = max(4.8, 2.7 * uniqueN(x$standard_label)))
    portal_data$catalog[[sex]] <- list(
      traces = lapply(unique(x$standard_label), function(lab) trace_line(x[standard_label == lab], "exact_age", "ex", lab, "#1D4ED8", extra = "e(x): ")),
      layout = list(title = paste0("Catálogo por sexo: ", sex), xaxis = list(title = "Edad simple", dtick = 10), yaxis = list(title = "e(x) en años"), hovermode = "closest"),
      profile_png = rel(path)
    )
    catalog_manifest <- rbind(catalog_manifest, data.table(sex_source_value = sex, profile_png = rel(path)), fill = TRUE)
  }

  terminal_selections <- unique(sa[, .(standard_source, standard_version, sex_source_value)])
  setorder(terminal_selections, standard_source, standard_version, sex_source_value)
  terminal_plot_manifest <- data.table()

  for (i in seq_len(nrow(terminal_selections))) {
    z <- terminal_selections[i]
    tid <- paste(slug(z$standard_source), slug(z$standard_version), slug(z$sex_source_value), sep = "_")
    final_tail <- sa[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value & exact_age >= 75]
    ex_tail <- support_ex[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value & exact_age >= 75]
    abr_tail <- abr_int[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value & age_start >= 75]
    curve_dt <- rbind(data.table(version = final_curve_label, exact_age = final_tail$exact_age, ex = final_tail$ex), data.table(version = benchmark_curve_label, exact_age = ex_tail$exact_age, ex = ex_tail$ex), fill = TRUE)
    delta_dt <- copy(curve_dt); setorder(delta_dt, version, exact_age); delta_dt[, delta := c(NA_real_, diff(ex)), by = version]
    curv_dt <- copy(delta_dt[!is.na(delta)]); curv_dt[, second_diff := c(NA_real_, diff(delta)), by = version]
    sel_final <- selected_methods[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value & family == "law_based"]
    sel_ex <- selected_methods[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value & family == "ex_space"]
    term_one <- terminal_summary[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value]
    compare_one <- compare_tail[standard_source == z$standard_source & standard_version == z$standard_version & sex_source_value == z$sex_source_value]

    curve_fp <- file.path(plot_dir, paste0("terminal_curve_", tid, ".png"))
    delta_fp <- file.path(plot_dir, paste0("terminal_delta_", tid, ".png"))
    curv_fp <- file.path(plot_dir, paste0("terminal_curvature_", tid, ".png"))
    ggsave(curve_fp, ggplot(curve_dt, aes(exact_age, ex, color = version, linetype = version)) + geom_line(linewidth = 1) + geom_point(data = abr_tail[, .(exact_age = age_start, ex)], aes(exact_age, ex), inherit.aes = FALSE, color = pal[[z$sex_source_value]], shape = 21, fill = "white", stroke = 0.8, size = 2.2) + scale_color_manual(values = cmp_pal) + scale_linetype_manual(values = c("Método final contractual" = "solid", "Comparador en espacio de e(x)" = "22")) + scale_x_continuous(breaks = seq(75, 125, 5)) + labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": curva terminal"), subtitle = "El método final se baso en una ley de mortalidad avanzada; el comparador en espacio de e(x) se mantuvo como referencia reproducible.", x = "Edad exacta / soporte interno", y = "e(x)") + tportal(), width = 10.6, height = 5.8, dpi = 180, bg = "white")
    ggsave(delta_fp, ggplot(delta_dt[exact_age >= 80 & !is.na(delta)], aes(exact_age, delta, color = version, linetype = version)) + geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) + geom_line(linewidth = 1) + scale_color_manual(values = cmp_pal) + scale_linetype_manual(values = c("Método final contractual" = "solid", "Comparador en espacio de e(x)" = "22")) + scale_x_continuous(breaks = seq(80, 125, 5)) + labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": delta anual en cola"), subtitle = "Después de 85, el delta se interpreta como evidencia del cierre modelado y no como observación directa de la fuente.", x = "Edad exacta / soporte interno", y = "delta de e(x)") + tportal(), width = 10.6, height = 5.2, dpi = 180, bg = "white")
    ggsave(curv_fp, ggplot(curv_dt[exact_age >= 81 & !is.na(second_diff)], aes(exact_age, second_diff, color = version, linetype = version)) + geom_hline(yintercept = 0, color = "#7B8794", linewidth = 0.6) + geom_line(linewidth = 1) + scale_color_manual(values = cmp_pal) + scale_linetype_manual(values = c("Método final contractual" = "solid", "Comparador en espacio de e(x)" = "22")) + scale_x_continuous(breaks = seq(80, 125, 5)) + labs(title = paste0(z$standard_source, " / ", z$standard_version, " / ", z$sex_source_value, ": curvatura de cola"), subtitle = "La segunda diferencia discreta ayuda a detectar quiebres y cambios de forma del cierre.", x = "Edad exacta / soporte interno", y = "segunda diferencia") + tportal(), width = 10.6, height = 5.2, dpi = 180, bg = "white")

    portal_data$terminal[[tid]] <- list(
      source = z$standard_source,
      version = z$standard_version,
      sex = z$sex_source_value,
      method_final = sel_final$selected_method[1],
      method_benchmark = sel_ex$selected_method[1],
      ex_110plus = term_one$ex_110plus[1],
      curve = list(traces = list(trace_line(final_tail, "exact_age", "ex", final_curve_label, cmp_pal[[final_curve_label]], extra = "e(x): "), trace_line(ex_tail, "exact_age", "ex", benchmark_curve_label, cmp_pal[[benchmark_curve_label]], dash = "dash", extra = "e(x): "), trace_marker(abr_tail, "age_start", "ex", abridged_points_label, pal[[z$sex_source_value]], extra = "e(x): ")), layout = list(title = "Curva terminal y 110+", xaxis = list(title = "Edad exacta / soporte interno", dtick = 5), yaxis = list(title = "e(x)"), hovermode = "closest")),
      delta = list(traces = list(trace_line(delta_dt[version == final_curve_label & !is.na(delta) & exact_age >= 80], "exact_age", "delta", final_curve_label, cmp_pal[[final_curve_label]], extra = "Delta e(x): "), trace_line(delta_dt[version == benchmark_curve_label & !is.na(delta) & exact_age >= 80], "exact_age", "delta", benchmark_curve_label, cmp_pal[[benchmark_curve_label]], dash = "dash", extra = "Delta e(x): ")), layout = list(title = "Delta anual en cola", xaxis = list(title = "Edad exacta / soporte interno", dtick = 5), yaxis = list(title = "Delta e(x)"), hovermode = "closest", shapes = list(list(type = "line", x0 = 80, x1 = 125, y0 = 0, y1 = 0, line = list(color = "#7B8794", dash = "dot"))))),
      curvature = list(traces = list(trace_line(curv_dt[version == final_curve_label & !is.na(second_diff) & exact_age >= 81], "exact_age", "second_diff", final_curve_label, cmp_pal[[final_curve_label]], extra = "Curvatura: "), trace_line(curv_dt[version == benchmark_curve_label & !is.na(second_diff) & exact_age >= 81], "exact_age", "second_diff", benchmark_curve_label, cmp_pal[[benchmark_curve_label]], dash = "dash", extra = "Curvatura: ")), layout = list(title = "Curvatura terminal", xaxis = list(title = "Edad exacta / soporte interno", dtick = 5), yaxis = list(title = "Segunda diferencia"), hovermode = "closest", shapes = list(list(type = "line", x0 = 81, x1 = 125, y0 = 0, y1 = 0, line = list(color = "#7B8794", dash = "dot"))))),
      compare_html = table_html(compare_one[, .(exact_age, ex_final, ex_ex_space, final_minus_ex_space)], max_rows = 18, digits = 4, header_labels = list(exact_age = "Edad", ex_final = final_curve_label, ex_ex_space = benchmark_curve_label, final_minus_ex_space = "Diferencia final - comparador"))
    )
    terminal_plot_manifest <- rbind(terminal_plot_manifest, data.table(standard_source = z$standard_source, standard_version = z$standard_version, sex_source_value = z$sex_source_value, curve_png = rel(curve_fp), delta_png = rel(delta_fp), curvature_png = rel(curv_fp)), fill = TRUE)
  }

  catalog_delta <- delta[!is.na(delta_ex), .(mean_abs_delta = mean(abs_delta_ex), max_abs_delta = max(abs_delta_ex)), by = .(sex_source_value, standard_source, standard_version)]
  glossary_export <- copy(glossary)[, .(
    categoria = category,
    termino_visible = label,
    nombre_tecnico = technical_name,
    definicion = definition,
    formula = formula,
    lectura_ok = ok_pattern,
    lectura_revisar = review_pattern,
    enlace_anexo = fifelse(is.na(annex_anchor) | annex_anchor == "", "", paste0("../auditoria_tabla_vida_estandar.html#", annex_anchor))
  )]
  fingerprint_summary <- rbind(
    data.table(table = "abridged", rows = nrow(abr), cols = abr_cols, age_key = "age_start", grain = "standard_source / standard_version / sex_id / age_start"),
    data.table(table = "single_age", rows = nrow(sa), cols = sa_cols, age_key = "exact_age", grain = "standard_source / standard_version / sex_id / exact_age")
  )
  fingerprint_detail <- rbind(
    data.table(table = "abridged", path = file.path(p$FINAL_DIR, "life_table_standard_reference_abridged.csv"), dictionary = file.path(p$FINAL_DIR, "life_table_standard_reference_abridged_dictionary_ext.csv")),
    data.table(table = "single_age", path = file.path(p$FINAL_DIR, "life_table_standard_reference_single_age.csv"), dictionary = file.path(p$FINAL_DIR, "life_table_standard_reference_single_age_dictionary_ext.csv"))
  )
  qc_summary_visible <- qc_summary[, .(
    dataset = fifelse(dataset == "abridged", "Abridged", "Edad simple"),
    check_name = vapply(check_name, human_check_html, character(1)),
    status,
    n_rows
  )]
  knot_summary_visible <- knot_summary[, .(
    standard_source,
    standard_version,
    sex_source_value,
    n_knots,
    n_missing_single_age,
    max_abs_diff,
    mean_abs_diff
  )]
  terminal_summary_visible <- terminal_summary[, .(
    standard_source,
    standard_version,
    sex_source_value,
    terminal_label_export,
    ex_85,
    ex_109,
    ex_110plus,
    monotone_expected = fbool(monotone_expected),
    terminal_policy_current = fifelse(terminal_policy_current == "positive_open_ex", "110+ abierto con e(x) positiva", terminal_policy_current)
  )]
  terminal_summary_detail <- terminal_summary[, .(
    standard_source, standard_version, sex_id, sex_source_value, min_exact_age, max_exact_age, n_open,
    terminal_age_export, terminal_open_flag, terminal_label_export, ex_85, ex_109, ex_110plus,
    monotone_full, monotone_expected, terminal_policy_current, open_age_source, open_age_end_source,
    open_age_label_source, ex_open_source, contract_v2_impact, support_age_max
  )]
  method_summary_visible <- method_summary[, .(
    family = vapply(family, human_family_html, character(1)),
    method = vapply(method, human_method_html, character(1)),
    n_strata,
    median_jump_84_85,
    median_rebound_ratio_95,
    median_ex_110plus
  )]
  selected_methods_visible <- selected_methods[, .(
    standard_source,
    standard_version,
    sex_source_value,
    family = vapply(family, human_family_html, character(1)),
    selected_method = vapply(selected_method, human_method_html, character(1)),
    ex_110plus,
    delta_pattern = fifelse(delta_pattern == "closure-driven", "Domina el cierre modelado", fifelse(delta_pattern == "stable", "Estable", delta_pattern)),
    score
  )]
  method_detail_visible <- method_detail[, .(
    standard_source,
    standard_version,
    sex_source_value,
    family = vapply(family, human_family_html, character(1)),
    method = vapply(method, human_method_html, character(1)),
    ex_110plus,
    jump_84_85,
    rebound_ratio_95,
    score
  )]
  catalog_delta_visible <- copy(catalog_delta)
  setnames(catalog_delta_visible, c("sex_source_value", "standard_source", "standard_version", "mean_abs_delta", "max_abs_delta"), c("sexo", "fuente", "version", "delta_medio_absoluto", "delta_máximo_absoluto"))
  direct_tomo_links <- c(
    "<a class=\"btn\" href=\"tomos/tomo_qc_resumen_standard_life_table.pdf\">QC resumen</a>",
    vapply(seq_len(nrow(meta)), function(i) {
      z <- meta[i]
      paste0(
        "<a class=\"btn\" href=\"tomos/tomo_coherencia_", slug(z$standard_source), "_", slug(z$standard_version), ".pdf\">",
        esc(z$standard_source), " / ", esc(z$standard_version), "</a>"
      )
    }, character(1))
  )
  direct_tomo_links_html <- paste(direct_tomo_links, collapse = "")
  fwrite(selections[, .(standard_source, standard_version, sex_mode, sex_label)], file.path(download_dir, "selection_manifest.csv"))
  fwrite(panel_meta, file.path(download_dir, "panel_summary.csv"))
  fwrite(plot_manifest, file.path(download_dir, "interactive_plot_manifest.csv"))
  fwrite(catalog_manifest, file.path(download_dir, "catalog_profile_manifest.csv"))
  fwrite(terminal_plot_manifest, file.path(download_dir, "terminal_plot_manifest.csv"))
  fwrite(catalog_delta, file.path(download_dir, "catalog_delta_summary.csv"))
  fwrite(glossary_export, file.path(download_dir, "glosario_terminos_portal.csv"))
  fwrite(sa[, .(rows = .N, min_age = min(exact_age), max_age = max(exact_age), e0 = ex[which.min(exact_age)], terminal_ex = ex[which.max(exact_age)]), by = .(standard_source, standard_version, sex_source_value)], file.path(download_dir, "summary_single_age_by_standard_sex.csv"))
  fwrite(abr[, .(rows = .N, min_age_start = min(age_start), max_age_start = max(age_start), min_ex = min(ex), max_ex = max(ex)), by = .(standard_source, standard_version, sex_source_value)], file.path(download_dir, "summary_abridged_by_standard_sex.csv"))
  fwrite(knot, file.path(download_dir, "knot_single_age_vs_abridged_comparison.csv"))
  fwrite(delta[!is.na(delta_ex)][order(-abs_delta_ex), .(standard_source, standard_version, sex_source_value, exact_age, age_band, ex, delta_ex, abs_delta_ex)][1:min(.N, 50)], file.path(download_dir, "ranking_largest_single_age_delta_ex.csv"))
  qc_files <- list.files(p$QC_DIR, pattern = "^qc_standard_life_table_.*\\.(csv|png)$", full.names = TRUE)
  fwrite(data.table(file = basename(qc_files), bytes = file.info(qc_files)$size), file.path(download_dir, "qc_input_files_manifest.csv"))
  fwrite(selected_methods, file.path(download_dir, "single_age_tail_selected_methods.csv"))
  fwrite(terminal_summary, file.path(download_dir, "qc_standard_life_table_terminal_summary.csv"))
  fwrite(method_summary, file.path(download_dir, "single_age_tail_method_summary.csv"))
  wtxt(file.path(asset_dir, "portal_data.js"), paste0("window.portalData=", jsonlite::toJSON(portal_data, auto_unbox = TRUE, dataframe = "rows", null = "null"), ";"))
  category_labels <- c(
    bioestadística = "Conceptos bioestadisticos y demográficos",
    qc = "Controles de QC y estructura",
    metric = "Metricas de interpretacion",
    method = "Familias y métodos de cierre",
    source = "Fuente, soporte interno y contrato"
  )
  glossary_sections_html <- paste(vapply(names(category_labels), function(cat) {
    dt <- glossary[category == cat]
    if (!nrow(dt)) return("")
    cards <- paste(vapply(seq_len(nrow(dt)), function(i) {
      row <- dt[i]
      bits <- c(
        paste0("<article class=\"glossary-card\"><h3>", esc(row$label), "</h3>"),
        paste0("<p class=\"glossary-tech\">Nombre técnico: ", esc(row$technical_name), "</p>"),
        paste0("<p>", esc(row$definition), "</p>")
      )
      if (!is.na(row$formula) && nzchar(row$formula)) bits <- c(bits, paste0("<p class=\"glossary-formula\">", esc(row$formula), "</p>"))
      bits <- c(bits, paste0("<p><strong>Patrón esperado:</strong> ", esc(row$ok_pattern), "</p>"), paste0("<p><strong>Señal de alerta:</strong> ", esc(row$review_pattern), "</p>"))
      if (!is.na(row$annex_anchor) && nzchar(row$annex_anchor)) bits <- c(bits, paste0("<p><a class=\"tooltip-link\" href=\"../auditoria_tabla_vida_estandar.html#", esc(row$annex_anchor), "\">Ver anexo metodológico</a></p>"))
      bits <- c(bits, "</article>")
      paste(bits, collapse = "")
    }, character(1)), collapse = "")
    paste0("<section class=\"glossary-section\"><div class=\"section-head\"><div><h2>", esc(category_labels[[cat]]), "</h2><p>Términos usados en tablas, gráficos y controles visibles del portal.</p></div><div class=\"section-meta\">Glosario</div></div><div class=\"glossary-grid\">", cards, "</div></section>")
  }, character(1)), collapse = "")

  css <- c(
    ":root{--bg:#F4F7FB;--surface:#FFFFFF;--soft:#F8FBFF;--soft2:#F8FAFC;--ink:#102A43;--muted:#486581;--line:#D9E2EC;--line2:#BCCCDC;--accent:#0F766E;--accent2:#1D4ED8;--warn:#B45309;--ok:#166534;--alert:#B42318;--shadow:0 10px 26px rgba(16,42,67,.08)}",
    "*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;font-family:Inter,Segoe UI,Arial,Helvetica,sans-serif;background:var(--bg);color:var(--ink);line-height:1.55}a{color:#1D4ED8;text-decoration:none}a:hover{text-decoration:underline}",
    ".site-header{padding:24px 6vw 18px;background:linear-gradient(180deg,#fff 0%,#F7FBFF 100%);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:30}.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--accent);font-weight:700}.site-header-inner{display:grid;gap:10px;max-width:1180px}.hero-text{display:grid;gap:10px;max-width:1040px}.hero-meta{font-size:13px;color:var(--muted);max-width:980px}h1{font-size:30px;line-height:1.1;margin:0}h2{font-size:22px;line-height:1.18;margin:0 0 8px}h3{font-size:18px;line-height:1.2;margin:0 0 8px}h4{font-size:15px;margin:0 0 8px}.lede{font-size:15px;color:var(--muted);max-width:960px;margin:0}.muted{color:var(--muted)}.small-note{font-size:12px;color:var(--muted);margin-top:8px}",
    "main{padding:20px 6vw 48px;overflow-x:hidden}.notice{border:1px solid #FCD34D;background:#FFF7ED;border-left:4px solid var(--warn);padding:12px 14px;border-radius:8px}.context-note{display:flex;gap:10px;align-items:flex-start;border:1px solid #FCD34D;background:#FFF7ED;padding:12px 14px;border-radius:8px}.context-note strong{display:block;margin-bottom:2px}.metric-grid,.summary-grid,.download-grid,.catalog-grid{display:grid;gap:14px}.metric-grid{grid-template-columns:repeat(auto-fit,minmax(180px,1fr))}.summary-grid{grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}.download-grid{grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}.catalog-grid{grid-template-columns:repeat(auto-fit,minmax(320px,1fr))}",
    ".metric-card,.summary-card,.download-card,.section-card,.catalog-card{background:var(--surface);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:16px}.metric-label{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.03em}.metric-value{font-size:28px;font-weight:800;margin-top:8px}.metric-sub{font-size:12px;color:var(--muted);margin-top:4px}.top-actions,.quick-links,.view-tabs{display:flex;gap:8px;flex-wrap:wrap}.btn{display:inline-flex;align-items:center;justify-content:center;padding:8px 12px;border-radius:8px;border:1px solid var(--line2);background:#fff;color:var(--ink);font-weight:700;font-size:13px;cursor:pointer}.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}.btn.secondary{background:#EFF6FF;border-color:#BFDBFE;color:#1D4ED8}.btn-tab.active{background:var(--ink);border-color:var(--ink);color:#fff}",
    ".fold-section{margin-top:14px}.fold-section>summary{list-style:none;display:flex;align-items:flex-start;justify-content:space-between;gap:12px;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:14px 16px;box-shadow:var(--shadow);cursor:pointer}.fold-section>summary::-webkit-details-marker{display:none}.fold-title{font-size:18px;font-weight:800;color:var(--ink)}.fold-subtitle{font-size:12px;color:var(--muted);text-align:right;max-width:420px;line-height:1.4}.fold-body{padding-top:12px;display:grid;gap:14px}",
    ".controls-shell{display:grid;gap:12px;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:16px;box-shadow:var(--shadow)}.controls-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}label{display:block;font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.03em;color:var(--muted);margin-bottom:6px}select{width:100%;padding:10px 12px;border:1px solid var(--line2);border-radius:8px;background:#fff;color:var(--ink);font-size:14px}",
    ".chips,.summary-chips{display:flex;gap:8px;flex-wrap:wrap}.chip{display:inline-flex;flex-direction:column;gap:2px;padding:8px 10px;border-radius:8px;border:1px solid var(--line);background:var(--soft);font-size:12px;color:var(--muted)}.chip strong{font-size:11px;text-transform:uppercase}.badge{display:inline-flex;align-items:center;padding:4px 8px;border-radius:999px;font-size:12px;font-weight:800;border:1px solid transparent}.badge.ok{background:#F0FDF4;color:var(--ok);border-color:#BBF7D0}.badge.alert{background:#FEF3F2;color:var(--alert);border-color:#FECACA}",
    ".coherence-panel,.terminal-panel{display:none;gap:14px}.coherence-panel.active,.terminal-panel.active{display:grid}.plot-frame{display:none;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:12px;box-shadow:var(--shadow)}.plot-frame.active{display:block}.plot-box{width:100%;height:430px}.plot-box.short{height:390px}.guide{font-size:13px;color:var(--muted);margin:0 0 10px}.state-card{border:1px solid var(--line);border-radius:8px;padding:16px;background:#fff}.ok-state{background:#F0FDF4;border-color:#BBF7D0}",
    ".table-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;background:#fff}.table-wrap.summary{overflow-x:auto}.table-wrap.technical{overflow:auto;max-width:100%}table{border-collapse:separate;border-spacing:0;width:100%;background:#fff}.summary-table{table-layout:fixed;min-width:0}.technical-table{table-layout:auto;min-width:820px}th,td{padding:10px;border-bottom:1px solid var(--line);vertical-align:top;font-size:13px;overflow-wrap:anywhere;word-break:break-word}th{position:sticky;top:0;background:var(--soft2);color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:.03em;text-align:left}tr:nth-child(even) td{background:#FCFDFF}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}",
    ".subdetails{margin-top:10px;border:1px solid var(--line);border-radius:8px;background:#fff}.subdetails>summary{cursor:pointer;list-style:none;padding:12px 14px;font-weight:700;color:var(--ink);background:#FBFDFF}.subdetails>summary::-webkit-details-marker{display:none}.subdetails-body{padding:0 14px 14px}.section-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:10px}.section-head p{margin:0;color:var(--muted);max-width:760px}.section-meta{font-size:12px;color:var(--muted)}.interpret-box{margin:10px 0 12px;padding:12px 14px;border-radius:8px;background:#F8FBFF;border:1px solid #D9E2EC}.interpret-box h4{margin:0 0 8px}.interpret-box p{margin:6px 0;color:var(--muted)}.table-note{margin:8px 0 0;color:var(--muted);font-size:12px}.info-term{position:relative;display:inline-flex;align-items:center;gap:4px;max-width:100%}.term-text{display:inline}.info-icon{display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;border-radius:999px;background:#EFF6FF;border:1px solid #BFDBFE;color:#1D4ED8;font-size:11px;font-weight:800;line-height:1;flex:0 0 18px}.tooltip-box{position:absolute;left:0;top:calc(100% + 8px);z-index:50;width:min(340px,75vw);display:none;padding:10px 12px;border-radius:8px;background:#102A43;color:#F8FAFC;box-shadow:0 10px 24px rgba(15,23,42,.26);font-size:12px;line-height:1.45;text-transform:none}.tooltip-box strong{display:block;margin-bottom:4px;color:#FFFFFF}.tooltip-tech{display:block;color:#D9E2EC;font-size:11px;margin-bottom:4px}.tooltip-formula{display:block;margin-top:4px;padding:6px 8px;border-radius:6px;background:rgba(255,255,255,.08);font-family:Consolas,Monaco,monospace}.tooltip-link{display:inline-block;margin-top:8px;color:#BFDBFE;font-weight:700}.tooltip-link:hover{color:#DBEAFE}.info-term:hover .tooltip-box,.info-term:focus-within .tooltip-box{display:block}.glossary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}.glossary-card{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:16px;box-shadow:var(--shadow)}.glossary-tech{font-size:12px;color:var(--muted)}.glossary-formula{padding:8px 10px;border-radius:8px;background:#F8FAFC;border:1px solid var(--line);font-family:Consolas,Monaco,monospace;font-size:12px}.glossary-section{display:grid;gap:12px}",
    ".footer-note{margin-top:22px;font-size:12px;color:var(--muted)}pre{margin:0;padding:12px 14px;border-radius:8px;background:#0F172A;color:#E2E8F0;overflow:auto;font-size:12px}@media(max-width:900px){main,.site-header{padding-left:18px;padding-right:18px}h1{font-size:26px}.fold-section>summary{flex-direction:column;align-items:flex-start}.fold-subtitle{text-align:left;max-width:none}.section-head{flex-direction:column}}"
  )
  wtxt(file.path(asset_dir, "portal.css"), css)

  js <- c(
    "const coherenceSelections=", toJSON(selections[, .(standard_source, standard_version, sex_mode, sex_label, panel_id = paste(slug(standard_source), slug(standard_version), slug(sex_mode), sep = '_'))], auto_unbox = TRUE, dataframe = "rows"), ";",
    "const terminalSelections=", toJSON(terminal_selections[, .(standard_source, standard_version, sex_source_value, panel_id = paste(slug(standard_source), slug(standard_version), slug(sex_source_value), sep = '_'))], auto_unbox = TRUE, dataframe = "rows"), ";",
    "function uniqBy(rows,key){const out=[],seen=new Set();rows.forEach(r=>{if(!seen.has(r[key])){seen.add(r[key]);out.push(r);}});return out;}",
    "function fillSelect(el,rows,valKey,labelKey,wanted){if(!el)return;const prev=wanted||el.value;el.innerHTML='';rows.forEach(r=>{const o=document.createElement('option');o.value=r[valKey];o.textContent=r[labelKey];el.appendChild(o);});const hit=rows.find(r=>r[valKey]===prev);el.value=hit?prev:(rows[0]?rows[0][valKey]:'');}",
    "function renderPlot(nodeId,payload,heightClass){const el=document.getElementById(nodeId);if(!el||!payload)return;if(payload.exact){el.innerHTML=`<div class='state-card ok-state'><h4>Preservación exacta</h4><p>Todos los knots abridged visibles en este estrato quedaron conservados sin error.</p><div class='chips'><span class='chip'><strong>Knots</strong><span>${payload.knots}</span></span><span class='chip'><strong>Error máximo</strong><span>${payload.max_error.toFixed(3)}</span></span></div></div>`;return;}const layout=Object.assign({paper_bgcolor:'#FFFFFF',plot_bgcolor:'#FFFFFF',margin:{l:60,r:25,t:60,b:55},legend:{orientation:'h',y:-0.22},font:{family:'Inter,Segoe UI,Arial,sans-serif',color:'#102A43'}},payload.layout||{});Plotly.react(el,payload.traces,layout,{displayModeBar:false,responsive:true});if(heightClass)el.classList.add(heightClass);}",
    "function syncCoherenceFilters(){const src=document.getElementById('standard_source'),ver=document.getElementById('standard_version'),sex=document.getElementById('sex_mode');fillSelect(src,uniqBy(coherenceSelections,'standard_source').map(x=>({standard_source:x.standard_source,label:x.standard_source})),'standard_source','label',src.value);fillSelect(ver,uniqBy(coherenceSelections.filter(x=>x.standard_source===src.value),'standard_version').map(x=>({standard_version:x.standard_version,label:x.standard_version})),'standard_version','label',ver.value);fillSelect(sex,coherenceSelections.filter(x=>x.standard_source===src.value&&x.standard_version===ver.value).map(x=>({sex_mode:x.sex_mode,label:x.sex_label})),'sex_mode','label',sex.value);}",
    "function showCoherence(){syncCoherenceFilters();const src=document.getElementById('standard_source').value;const ver=document.getElementById('standard_version').value;const sex=document.getElementById('sex_mode').value;const sel=coherenceSelections.find(x=>x.standard_source===src&&x.standard_version===ver&&x.sex_mode===sex);document.querySelectorAll('.coherence-panel').forEach(p=>p.classList.toggle('active',sel&&p.dataset.panelId===sel.panel_id));document.getElementById('empty_panel').style.display=sel?'none':'block';if(!sel)return;const payload=window.portalData.coherence[sel.panel_id];document.getElementById('selection_summary').textContent=`${payload.source} / ${payload.version} / ${payload.sex_label}`;['curve','delta','knots'].forEach(view=>renderPlot(`plot_${view}_${sel.panel_id}`,payload[view],view==='knots'?'short':''));document.getElementById(`table_${sel.panel_id}`).innerHTML=payload.table_html;activateView('coherence','curve');}",
    "function syncTerminalFilters(){const src=document.getElementById('terminal_source'),ver=document.getElementById('terminal_version'),sex=document.getElementById('terminal_sex');fillSelect(src,uniqBy(terminalSelections,'standard_source').map(x=>({standard_source:x.standard_source,label:x.standard_source})),'standard_source','label',src.value);fillSelect(ver,uniqBy(terminalSelections.filter(x=>x.standard_source===src.value),'standard_version').map(x=>({standard_version:x.standard_version,label:x.standard_version})),'standard_version','label',ver.value);fillSelect(sex,terminalSelections.filter(x=>x.standard_source===src.value&&x.standard_version===ver.value).map(x=>({sex_source_value:x.sex_source_value,label:x.sex_source_value})),'sex_source_value','label',sex.value);}",
    "function showTerminal(){syncTerminalFilters();const src=document.getElementById('terminal_source').value;const ver=document.getElementById('terminal_version').value;const sex=document.getElementById('terminal_sex').value;const sel=terminalSelections.find(x=>x.standard_source===src&&x.standard_version===ver&&x.sex_source_value===sex);document.querySelectorAll('.terminal-panel').forEach(p=>p.classList.toggle('active',sel&&p.dataset.panelId===sel.panel_id));document.getElementById('empty_terminal_panel').style.display=sel?'none':'block';if(!sel)return;const payload=window.portalData.terminal[sel.panel_id];document.getElementById('terminal_summary_label').textContent=`${payload.source} / ${payload.version} / ${payload.sex}`;document.getElementById(`terminal_meta_${sel.panel_id}`).innerHTML=`<div class='summary-chips'><span class='chip'><strong>Método final</strong><span>${payload.method_final}</span></span><span class='chip'><strong>Comparador</strong><span>${payload.method_benchmark}</span></span><span class='chip'><strong>e(110+)</strong><span>${Number(payload.ex_110plus).toFixed(3)}</span></span><span class='chip'><strong>Soporte interno</strong><span>hasta 125</span></span></div>`;['curve','delta','curvature'].forEach(view=>renderPlot(`plot_terminal_${view}_${sel.panel_id}`,payload[view],view==='curvature'?'short':''));document.getElementById(`terminal_table_${sel.panel_id}`).innerHTML=payload.compare_html;activateView('terminal','curve');}",
    "function activateView(scope,view){document.querySelectorAll(`.${scope}-tabs .btn-tab`).forEach(b=>b.classList.toggle('active',b.dataset.view===view));document.querySelectorAll(`.${scope}-panel.active .plot-frame`).forEach(f=>f.classList.toggle('active',f.dataset.view===view));document.querySelectorAll(`.${scope}-panel.active .plot-frame.active .plot-box`).forEach(el=>{if(window.Plotly){try{Plotly.Plots.resize(el);}catch(e){}}});}",
    "function renderCatalog(){Object.keys(window.portalData.catalog).forEach(sex=>renderPlot(`catalog_${sex.toLowerCase()}`,window.portalData.catalog[sex],''));}",
    "document.addEventListener('DOMContentLoaded',()=>{document.querySelectorAll('.coherence-tabs .btn-tab').forEach(btn=>btn.addEventListener('click',()=>activateView('coherence',btn.dataset.view)));document.querySelectorAll('.terminal-tabs .btn-tab').forEach(btn=>btn.addEventListener('click',()=>activateView('terminal',btn.dataset.view)));['standard_source','standard_version','sex_mode'].forEach(id=>document.getElementById(id).addEventListener('change',showCoherence));['terminal_source','terminal_version','terminal_sex'].forEach(id=>document.getElementById(id).addEventListener('change',showTerminal));renderCatalog();showCoherence();showTerminal();});"
  )
  wtxt(file.path(asset_dir, "portal.js"), js)

  first_panel <- paste(slug(selections$standard_source[1]), slug(selections$standard_version[1]), slug(selections$sex_mode[1]), sep = "_")
  first_terminal <- paste(slug(terminal_selections$standard_source[1]), slug(terminal_selections$standard_version[1]), slug(terminal_selections$sex_source_value[1]), sep = "_")

  coherence_panels_html <- paste(vapply(seq_len(nrow(selections)), function(i) {
    s <- selections[i]
    pid <- paste(slug(s$standard_source), slug(s$standard_version), slug(s$sex_mode), sep = "_")
    payload <- portal_data$coherence[[pid]]
    paste0(
      "<section class=\"coherence-panel", ifelse(pid == first_panel, " active", ""), "\" data-panel-id=\"", pid, "\">",
      "<div class=\"section-card\"><div class=\"panel-head\"><div><h3>", esc(payload$source), " / ", esc(payload$version), "</h3><p class=\"muted\">", esc(payload$sex_label), ". Región y año no aplican en esta tabla estándar.</p></div>",
      "<div class=\"summary-chips\"><span class=\"chip\"><strong>Sexos</strong><span>", esc(payload$visible_sexes), "</span></span><span class=\"chip\"><strong>Edad</strong><span>", esc(payload$age_range), "</span></span><span class=\"chip\"><strong>e(0)</strong><span>", esc(payload$e0), "</span></span></div></div>",
      "<div class=\"plot-frame active\" data-view=\"curve\"><p class=\"guide\">El patrón esperado es una curva descendente plausible y puntos abridged superpuestos donde existen puntos observados. Separaciones visibles entre linea y puntos sugieren revisar la expansión.</p><div class=\"plot-box\" id=\"plot_curve_", pid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"delta\"><p class=\"guide\">Aquí se buscan saltos locales. Antes de 85 debería verse continuidad entre puntos observados; después de 85 se interpreta la plausibilidad del cierre modelado, no una observación directa.</p><div class=\"plot-box\" id=\"plot_delta_", pid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"knots\"><p class=\"guide\">La lectura ideal es error 0 en todos los puntos observados visibles. Cualquier diferencia distinta de 0 significa que la expansión dejó de respetar la fuente en esos puntos.</p><div class=\"plot-box short\" id=\"plot_knots_", pid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"table\"><p class=\"guide\">Esta tabla prioriza edades con mayor cambio absoluto. Permite decidir en qué edades conviene examinar con más detalle la curva y el delta.</p><div id=\"table_", pid, "\"></div></div></div></section>"
    )
  }, character(1)), collapse = "\n")

  terminal_panels_html <- paste(vapply(seq_len(nrow(terminal_selections)), function(i) {
    z <- terminal_selections[i]
    tid <- paste(slug(z$standard_source), slug(z$standard_version), slug(z$sex_source_value), sep = "_")
    paste0(
      "<section class=\"terminal-panel", ifelse(tid == first_terminal, " active", ""), "\" data-panel-id=\"", tid, "\">",
      "<div class=\"section-card\"><div class=\"panel-head\"><div><h3>", esc(z$standard_source), " / ", esc(z$standard_version), " / ", esc(z$sex_source_value), "</h3><p class=\"muted\">La fuente solo observa 85+ como abierto. La forma posterior se modela y se audita de manera explícita.</p></div><div id=\"terminal_meta_", tid, "\"></div></div>",
      "<div class=\"plot-frame active\" data-view=\"curve\"><p class=\"guide\">Compara la cola contractual final con el comparador en espacio de e(x). El patrón esperado muestra transición suave desde 85 y e(110+) positiva sin un recorte artificial en cero.</p><div class=\"plot-box\" id=\"plot_terminal_curve_", tid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"delta\"><p class=\"guide\">Aquí se evalúa si el delta rebota hacia 0 de forma gradual o demasiado brusca. Un rebote excesivo suele delatar un cierre demasiado mecánico.</p><div class=\"plot-box short\" id=\"plot_terminal_delta_", tid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"curvature\"><p class=\"guide\">La curvatura resume cambios de pendiente. Valores moderados son compatibles con una cola suave; picos fuertes sugieren quiebre o rectificación excesiva.</p><div class=\"plot-box short\" id=\"plot_terminal_curvature_", tid, "\"></div></div>",
      "<div class=\"plot-frame\" data-view=\"compare\"><p class=\"guide\">Esta tabla muestra la diferencia puntual entre el contractual final y el comparador metodológico. Permite ver en qué edades ambos métodos realmente divergen.</p><div id=\"terminal_table_", tid, "\"></div></div></div></section>"
    )
  }, character(1)), collapse = "\n")

  catalog_cards_html <- paste(vapply(sort(unique(sa$sex_source_value)), function(sex) {
    sid <- tolower(sex)
    paste0("<article class=\"catalog-card\"><div class=\"plot-box short\" id=\"catalog_", sid, "\"></div></article>")
  }, character(1)), collapse = "\n")

  html <- c(
    "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Portal integrado - tabla de vida estándar</title><link rel=\"stylesheet\" href=\"assets/portal.css\">",
    "<script src=\"assets/plotlyjs/plotly-latest.min.js\"></script></head><body>",
    "<header class=\"site-header\"><div class=\"site-header-inner\"><div class=\"eyebrow\">tabla-vida-estándar / portal integrado</div><div class=\"hero-text\"><h1>Tabla de vida estándar: metodología, QC y cola terminal</h1>",
    "<p class=\"lede\">Portal único para revisar la salida final versionada, los controles principales, la forma de e(x) y el cierre terminal. Cada bloque incluye ayuda para interpretar qué patrón resulta esperable y qué hallazgo conviene revisar con más detalle.</p>",
    "<p class=\"hero-meta\">La tabla estándar es una referencia normativa y no se desagrega por región ni año. Utilicen esta página como puerta de entrada: primero revisen el estado general y el QC, luego las curvas, y finalmente la cola terminal cuando necesiten examinar el cierre posterior a 85.</p></div>",
    "<div class=\"top-actions\"><a class=\"btn primary\" href=\"#estado-general\">Estado general</a><a class=\"btn\" href=\"#curvas\">Curvas e(x)</a><a class=\"btn\" href=\"#cola-terminal\">Cola terminal</a><a class=\"btn\" href=\"../auditoria_tabla_vida_estandar.html\">Anexo metodológico</a><a class=\"btn\" href=\"glosario_terminos.html\">Glosario</a><a class=\"btn\" href=\"#descargas\">Descargas</a><a class=\"btn secondary\" href=\"tomos/indice_de_tomos_standard_life_table.pdf\">Tomos PDF</a></div></div></header>",
    "<main>",
    "<section class=\"metric-grid\">",
    paste0("<article class=\"metric-card\"><div class=\"metric-label\">Filas abridged</div><div class=\"metric-value\">", nrow(abr), "</div><div class=\"metric-sub\">salida contractual final</div></article>"),
    paste0("<article class=\"metric-card\"><div class=\"metric-label\">Filas single-age</div><div class=\"metric-value\">", nrow(sa), "</div><div class=\"metric-sub\">0:109 y 110+</div></article>"),
    paste0("<article class=\"metric-card\"><div class=\"metric-label\">Referencias</div><div class=\"metric-value\">", uniqueN(sa[, .(standard_source, standard_version)]), "</div><div class=\"metric-sub\">fuente / versión</div></article>"),
    paste0("<article class=\"metric-card\"><div class=\"metric-label\">Checks QC</div><div class=\"metric-value\">", nrow(qc_summary), "</div><div class=\"metric-sub\">incluyen cola terminal</div></article>"),
    "<article class=\"metric-card\"><div class=\"metric-label\">Soporte interno</div><div class=\"metric-value\">125</div><div class=\"metric-sub\">deriva ex(110+) positiva</div></article>",
    "</section>",
    "<details class=\"fold-section\" id=\"estado-general\" open><summary><span class=\"fold-title\">Estado general</span><span class=\"fold-subtitle\">Resumen del flujo reproducible, el contrato final y la evidencia de control.</span></summary><div class=\"fold-body\">",
    "<section class=\"summary-grid\"><article class=\"summary-card\"><h3>Contrato final</h3><p class=\"muted\">La salida contractual exporta edades 0:109 y un último grupo abierto 110+. En una corrida consistente, este bloque y el módulo terminal muestran e(110+) positiva y una cola coherente.</p></article>",
    "<article class=\"summary-card\"><h3>Fuente abierta 85+</h3><p class=\"muted\">La fuente original registra 85+ como intervalo abierto. El campo age_end = 120 funciona solo como codificación del abierto; la cola interna hasta 125 se utilizó como soporte de cálculo y no contradice la fuente.</p></article>",
    "<article class=\"summary-card\"><h3>Método final</h3><p class=\"muted\">La salida contractual utilizó una familia basada en ley de mortalidad seleccionada por estrato. El comparador en espacio de e(x) se mantuvo solo como referencia metodológica para auditar el cierre elegido.</p></article>",
    "<article class=\"summary-card\"><h3>Salida reproducible</h3><p class=\"muted\">Esta web concentra lectura guiada, control de calidad y descargas. En una lectura consistente deberían verse estados OK, preservación exacta de puntos observados y una cola terminal sin quiebres dominantes.</p></article></section>",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>Resumen QC</h2><p>Es la primera tabla a revisar. Resume controles estructurales y contractuales para establecer si la corrida concluyó sin incoherencias detectables.</p></div><div class=\"section-meta\">Vista resumida</div></div>", interpretation_box("Lo esperable es ver estado OK y n_rows = 0 en todos los controles visibles.", "Cualquier fila distinta de 0 o un estado distinto de OK indica una incoherencia real que debe revisarse antes de usar la salida."), table_html(qc_summary_visible, max_rows = 20, status_cols = "status", digits = 0, wrapper_class = "table-wrap summary", table_class = "summary-table", html_cols = "check_name", header_labels = list(dataset = "Tabla", check_name = "Control", status = "Estado", n_rows = "Filas con hallazgo")), table_note("Los nombres técnicos completos se conservan en los CSV descargables. En la capa visible se priorizó una lectura más directa."), "</section>",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>", tooltip_label("fingerprint", "Resumen de estructura y huella del output"), "</h2><p>Vista sintética del contractual final: qué tablas se generan, cuántas filas presentan y cuál es su variable de edad.</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("Los conteos y la granularidad deben verse estables entre corridas comparables.", "Cambios inesperados en filas, columnas o granularidad suelen indicar una alteración real del contrato."), table_html(fingerprint_summary, max_rows = 10, digits = 0, wrapper_class = "table-wrap summary", table_class = "summary-table", header_labels = list(table = "Tabla", rows = "Filas", cols = "Columnas", age_key = "Variable de edad", grain = "Granularidad lógica")), detail_block("Ver rutas y archivos asociados", table_html(fingerprint_detail, max_rows = 10, digits = 0, wrapper_class = "table-wrap technical", table_class = "technical-table", header_labels = list(table = "Tabla", path = "Ruta del CSV", dictionary = "Ruta del diccionario"))), "</section>",
    "</div></details>",
    "<details class=\"fold-section\" id=\"qc-tecnico\"><summary><span class=\"fold-title\">QC técnico</span><span class=\"fold-subtitle\">Controles estructurales, preservación de puntos observados y evidencia tabular descargable.</span></summary><div class=\"fold-body\">",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>Preservación de puntos observados</h2><p>Mide si la expansión final respetó exactamente los puntos abridged observados. Es uno de los chequeos principales para confiar en la expansión.</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("La lectura ideal es puntos observados faltantes = 0 y error máximo = 0. Eso significa que la expansión no alteró la fuente en las edades que debían preservarse.", "Si aparecen puntos observados faltantes o error mayor que 0, la expansión está modificando la fuente en edades que debían conservarse."), table_html(knot_summary_visible, max_rows = 12, digits = 4, wrapper_class = "table-wrap summary", table_class = "summary-table", header_labels = list(standard_source = "Fuente", standard_version = "Versión", sex_source_value = "Sexo", n_knots = tooltip_label("knot", "Puntos observados"), n_missing_single_age = tooltip_label("n_missing_single_age", "Puntos faltantes"), max_abs_diff = tooltip_label("max_abs_diff", "Error máximo"), mean_abs_diff = tooltip_label("mean_abs_diff", "Error medio"))), table_note("Cuando todos los errores valen 0, la expansión conserva exactamente los puntos abridged visibles para ese estrato."), "</section>",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>", tooltip_label("terminal_policy", "Política terminal por estrato"), "</h2><p>Resume cómo se representa el último intervalo 110+ y qué valor terminal se exporta en cada estrato.</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("El patrón esperado es ver e(110+) positiva, monotonicidad esperada = Sí cuando aplica y una política terminal consistente con un grupo abierto.", "Si e(110+) deja de ser positiva o la política terminal no coincide con el soporte interno, la cola requiere revisión."), table_html(terminal_summary_visible, max_rows = 12, digits = 3, wrapper_class = "table-wrap summary", table_class = "summary-table", header_labels = list(standard_source = "Fuente", standard_version = "Versión", sex_source_value = "Sexo", terminal_label_export = tooltip_label("terminal_open_interval", "Etiqueta exportada"), ex_85 = tooltip_label("ex", "e(85)"), ex_109 = tooltip_label("ex", "e(109)"), ex_110plus = tooltip_label("terminal_open_interval", "e(110+)"), monotone_expected = "Monotonicidad esperada", terminal_policy_current = tooltip_label("terminal_policy", "Política terminal"))), detail_block("Ver detalle técnico completo del 110+", table_html(terminal_summary_detail, max_rows = 12, digits = 3, wrapper_class = "table-wrap technical", table_class = "technical-table")), table_note("La fuente usa age_end = 120 para codificar 85+ abierto. El soporte interno hasta 125 solo se utilizó para construir una cola coherente y no redefine la fuente."), "</section>",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>", tooltip_label("benchmark", "Comparador de familias terminales"), "</h2><p>Compara familias de cierre para resumir continuidad local, rebote del delta y nivel terminal de e(110+).</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("Conviene leer esta tabla como comparación relativa entre familias: una familia consistente tiende a reducir quiebres sin forzar e(110+) a 0.", "Si una familia muestra rebote muy brusco o empuja e(110+) hacia 0, suele ser una señal de cierre demasiado mecánico."), table_html(method_summary_visible, max_rows = 10, digits = 4, wrapper_class = "table-wrap summary", table_class = "summary-table", html_cols = c("family", "method"), header_labels = list(family = "Familia", method = "Método", n_strata = "Estratos", median_jump_84_85 = tooltip_label("jump_84_85", "Quiebre mediano 84-85"), median_rebound_ratio_95 = tooltip_label("rebound_ratio_95", "Rebote mediano hacia 95"), median_ex_110plus = tooltip_label("terminal_open_interval", "e(110+) mediana"))), "</section></div></details>",
    "<details class=\"fold-section\" id=\"curvas\"><summary><span class=\"fold-title\">Curvas e(x)</span><span class=\"fold-subtitle\">Exploración guiada de forma, delta y preservación de puntos observados con hover exacto.</span></summary><div class=\"fold-body\">",
    "<section class=\"controls-shell\"><h2>Selección guiada</h2><p class=\"muted\">Utilicen este bloque para revisar la forma general por referencia. Un patrón esperado combina curva descendente plausible, delta sin saltos dominantes y preservación exacta de puntos observados.</p><div class=\"chips\"><span class=\"chip\"><strong>Panel activo</strong><span id=\"selection_summary\">cargando...</span></span></div>",
    "<div class=\"controls-grid\"><div><label for=\"standard_source\">Fuente de referencia</label><select id=\"standard_source\"></select></div><div><label for=\"standard_version\">Versión de la referencia</label><select id=\"standard_version\"></select></div><div><label for=\"sex_mode\">Vista por sexo</label><select id=\"sex_mode\"></select></div></div>",
    "<div class=\"view-tabs coherence-tabs\"><button class=\"btn btn-tab active\" type=\"button\" data-view=\"curve\">Curva e(x)</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"delta\">Delta anual</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"knots\">Puntos observados</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"table\">Tabla de hallazgos</button></div></section>",
    "<div id=\"empty_panel\" class=\"notice\" style=\"display:none\">No existe una combinación válida con esa selección.</div>", coherence_panels_html, "</div></details>",
    "<details class=\"fold-section\" id=\"catalogo\"><summary><span class=\"fold-title\">Catálogo resumido</span><span class=\"fold-subtitle\">Comparador por sexo para revisar con rapidez el nivel y la forma de e(x) entre referencias.</span></summary><div class=\"fold-body\"><section class=\"catalog-grid\">", catalog_cards_html, "</section><section class=\"section-card\"><div class=\"section-head\"><div><h2>Resumen del catálogo</h2><p>Resume la intensidad media y máxima del cambio anual por referencia. Ayuda a detectar referencias con deltas mucho más abruptos que el resto.</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("Valores del mismo orden entre referencias sugieren una lectura de catálogo consistente; luego corresponde confirmar la forma visual en las curvas.", "Si una referencia destaca con delta máxima muy superior al resto, conviene revisar si se trata de un rasgo esperado o de una cola demasiado forzada."), table_html(catalog_delta_visible, max_rows = 18, digits = 3, wrapper_class = "table-wrap summary", table_class = "summary-table", header_labels = list(sexo = "Sexo", fuente = "Fuente", version = "Versión", delta_medio_absoluto = tooltip_label("delta_ex", "Delta media absoluta"), delta_maximo_absoluto = tooltip_label("delta_ex", "Delta máxima absoluta"))), table_note("Este resumen no reemplaza la lectura visual. Solo ayuda a priorizar qué referencias merecen una revisión más cercana."), "</section></div></details>",
    "<details class=\"fold-section\" id=\"cola-terminal\"><summary><span class=\"fold-title\">Cola terminal y 110+</span><span class=\"fold-subtitle\">Comparación entre el método contractual final y el comparador en espacio de e(x) para cada estrato.</span></summary><div class=\"fold-body\">",
    "<div class=\"context-note\"><div><strong>Interpretación</strong><span>Desde 85 en adelante la fuente ya no aporta observación directa por edad simple: solo informa un intervalo abierto 85+ y lo codifica con age_end = 120. El soporte interno hasta 125 no contradice esa fuente; solo extiende el cálculo para construir un 110+ abierto con e(110+) positiva y una cola más coherente. En este bloque, curva, delta y curvatura se leen como evidencia del cierre modelado.</span></div></div>",
    "<section class=\"controls-shell\"><h2>Selección terminal</h2><p class=\"muted\">Este bloque permite evaluar si la cola final resulta metodológicamente plausible. Un patrón esperado combina transición suave alrededor de 85, rebote gradual del delta y e(110+) positiva sin forzar el tramo final hacia 0.</p><div class=\"chips\"><span class=\"chip\"><strong>Estrato activo</strong><span id=\"terminal_summary_label\">cargando...</span></span></div>",
    "<div class=\"controls-grid\"><div><label for=\"terminal_source\">Fuente de referencia</label><select id=\"terminal_source\"></select></div><div><label for=\"terminal_version\">Versión de la referencia</label><select id=\"terminal_version\"></select></div><div><label for=\"terminal_sex\">Sexo</label><select id=\"terminal_sex\"></select></div></div>",
    "<div class=\"view-tabs terminal-tabs\"><button class=\"btn btn-tab active\" type=\"button\" data-view=\"curve\">Curva</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"delta\">Delta</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"curvature\">Curvatura</button><button class=\"btn btn-tab\" type=\"button\" data-view=\"compare\">Comparación</button></div></section>",
    "<div id=\"empty_terminal_panel\" class=\"notice\" style=\"display:none\">No existe una combinación terminal válida con esa selección.</div>", terminal_panels_html,
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>Métodos seleccionados</h2><p>Resume qué familia resultó seleccionada en cada estrato y con qué patrón terminal concluyó el contractual final.</p></div><div class=\"section-meta\">Resumen visible</div></div>", interpretation_box("El patrón esperado es ver una familia coherente con e(110+) positiva y un delta dominado por un cierre plausible, no por un recorte artificial.", "Si el método seleccionado deja puntaje pobre, e(110+) muy baja o un patrón terminal claramente inestable, corresponde revisar ese estrato en los gráficos."), table_html(selected_methods_visible, max_rows = 20, digits = 4, wrapper_class = "table-wrap summary", table_class = "summary-table", html_cols = c("family", "selected_method"), header_labels = list(standard_source = "Fuente", standard_version = "Versión", sex_source_value = "Sexo", family = "Familia", selected_method = "Método seleccionado", ex_110plus = tooltip_label("terminal_open_interval", "e(110+)"), delta_pattern = tooltip_label("delta_ex", "Lectura del delta"), score = tooltip_label("score", "Puntaje"))), table_note("El nombre técnico exacto se conserva en las descargas. En esta vista se priorizó una lectura comparativa más directa."), "</section>",
    "<section class=\"section-card\"><div class=\"section-head\"><div><h2>Detalle de métodos candidatos</h2><p>Comparación analítica breve entre candidatos del comparador terminal. El detalle completo permanece disponible como CSV descargable.</p></div><div class=\"section-meta\">Detalle plegable</div></div>", interpretation_box("Lo esperable es preferir candidatos con quiebre 84-85 más bajo, rebote más gradual y e(110+) positiva sin rectificar la cola en exceso.", "Si un candidato mejora un indicador pero empeora claramente los demás, no conviene interpretarlo como ganador automático."), table_html(method_detail_visible, max_rows = 16, digits = 4, wrapper_class = "table-wrap summary", table_class = "summary-table", html_cols = c("family", "method"), header_labels = list(standard_source = "Fuente", standard_version = "Versión", sex_source_value = "Sexo", family = "Familia", method = "Método", ex_110plus = tooltip_label("terminal_open_interval", "e(110+)"), jump_84_85 = tooltip_label("jump_84_85", "Quiebre 84-85"), rebound_ratio_95 = tooltip_label("rebound_ratio_95", "Rebote hacia 95"), score = tooltip_label("score", "Puntaje"))), detail_block("Ver tabla técnica ampliada", table_html(method_detail, max_rows = 24, digits = 4, wrapper_class = "table-wrap technical", table_class = "technical-table")), table_note("Este bloque sirve para comparar candidatos dentro de un mismo estrato. Los puntajes no deben compararse entre familias sin examinar también los gráficos."), "</section></div></details>",
    "<details class=\"fold-section\" id=\"glosario\"><summary><span class=\"fold-title\">Glosario y ayudas</span><span class=\"fold-subtitle\">Definiciones formales, nombres técnicos, fórmulas y claves de interpretación.</span></summary><div class=\"fold-body\"><section class=\"section-card\"><div class=\"section-head\"><div><h2>Glosario del portal</h2><p>Si una sigla, un control o una métrica no resulta familiar, esta sección explica qué significa, cómo se calcula y qué patrón se considera esperado o de alerta.</p></div><div class=\"section-meta\">Ayuda de lectura</div></div><div class=\"quick-links\"><a class=\"btn primary\" href=\"glosario_terminos.html\">Abrir glosario completo</a><a class=\"btn\" href=\"downloads/glosario_terminos_portal.csv\">Descargar glosario CSV</a><a class=\"btn\" href=\"../auditoria_tabla_vida_estandar.html#sec-glosario-operativo\">Ir al anexo metodológico</a></div>", interpretation_box("La meta es que el portal pueda leerse sin memorizar nombres técnicos. La capa visible ya emplea etiquetas más claras y esta sección ofrece el detalle completo.", "Si aun después del tooltip y del glosario un término sigue siendo opaco, ese contenido debe seguir mejorándose."), table_note("Las descargas técnicas conservan los nombres originales para no perder auditabilidad. La capa visible utiliza etiquetas más directas cuando eso facilita la lectura."), "</section></div></details>",
    "<details class=\"fold-section\" id=\"descargas\"><summary><span class=\"fold-title\">Descargas y operación</span><span class=\"fold-subtitle\">Artefactos descargables, comandos de rerun y acceso a manuales.</span></summary><div class=\"fold-body\"><section class=\"download-grid\">",
    "<article class=\"download-card\"><h3>Portal web</h3><p class=\"muted\">Entrada principal del proyecto, glosario didáctico y módulo terminal de apoyo.</p><div class=\"quick-links\"><a class=\"btn\" href=\"index.html\">Portal principal</a><a class=\"btn\" href=\"glosario_terminos.html\">Glosario</a><a class=\"btn\" href=\"cola_terminal_110plus.html\">Módulo terminal</a><a class=\"btn\" href=\"../auditoria_tabla_vida_estandar.html\">Informe metodológico</a></div></article>",
    "<article class=\"download-card\"><h3>PDFs / tomos</h3><p class=\"muted\">Acceso directo al índice y a cada tomo individual sin pasar por una lista intermedia.</p><div class=\"quick-links\"><a class=\"btn secondary\" href=\"tomos/indice_de_tomos_standard_life_table.pdf\">Índice de tomos</a>", direct_tomo_links_html, "</div></article>",
    "<article class=\"download-card\"><h3>CSV / manifiestos</h3><p class=\"muted\">Filtros, paneles, QC terminal, glosario y artefactos descargables del portal.</p><div class=\"quick-links\"><a class=\"btn\" href=\"downloads/selection_manifest.csv\">Filtros</a><a class=\"btn\" href=\"downloads/panel_summary.csv\">Paneles</a><a class=\"btn\" href=\"downloads/interactive_plot_manifest.csv\">Gráficos</a><a class=\"btn\" href=\"downloads/qc_standard_life_table_terminal_summary.csv\">Resumen terminal</a><a class=\"btn\" href=\"downloads/single_age_tail_selected_methods.csv\">Métodos</a><a class=\"btn\" href=\"downloads/glosario_terminos_portal.csv\">Glosario CSV</a><a class=\"btn\" href=\"downloads/terminal_plot_manifest.csv\">Manifest terminal</a><a class=\"btn\" href=\"downloads/tomo_manifest.csv\">Manifest PDF</a></div></article>",
    "<article class=\"download-card\"><h3>Operación</h3><p class=\"muted\">Comandos base y documentos para ruta clásica, Docker, pseudocódigo y release final.</p><pre>Rscript scripts/run_preflight_checks.R\nRscript scripts/run_pipeline.R --profile full --clean-first\nquarto render README.qmd</pre><div class=\"quick-links\"><a class=\"btn\" href=\"../../docs/quickstart_first_use.md\">Quickstart</a><a class=\"btn\" href=\"../../docs/operations_manual.md\">Manual operativo</a><a class=\"btn\" href=\"../../docs/docker_manual.md\">Docker</a><a class=\"btn\" href=\"../../docs/pipeline_pseudocode.md\">Pseudocódigo</a><a class=\"btn\" href=\"../../docs/repo_minimal_release_manifest.md\">Repo mínimo</a></div></article>",
    "</section></div></details><p class=\"footer-note\">Generado por scripts/build_standard_life_table_portal.R. Los gráficos son interactivos sin Shiny y el contractual final mantiene 110+ abierto con e(x) positiva.</p></main>",
    "<script src=\"assets/portal_data.js\"></script><script src=\"assets/portal.js\"></script></body></html>"
  )
  wtxt(file.path(portal_dir, "index.html"), html)

  glossary_page <- c(
    "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<title>Glosario del portal - tabla de vida estándar</title>",
    "<link rel=\"stylesheet\" href=\"assets/portal.css\">",
    "</head><body><header class=\"site-header\"><div class=\"site-header-inner\">",
    "<div class=\"eyebrow\">TABLA-VIDA-ESTÁNDAR / GLOSARIO</div>",
    "<div class=\"hero-text\"><h1>Glosario del portal</h1>",
    "<p class=\"lede\">Esta página explica, en lenguaje claro y con detalle técnico, los términos visibles del portal. Incluye fórmulas cuando ayudan y una pauta de lectura para reconocer el patrón esperado y las señales de alerta.</p>",
    "<div class=\"top-actions\"><a class=\"btn primary\" href=\"index.html\">Volver al portal</a><a class=\"btn\" href=\"downloads/glosario_terminos_portal.csv\">Descargar glosario CSV</a><a class=\"btn\" href=\"../auditoria_tabla_vida_estandar.html\">Informe metodológico</a></div></div></div></header>",
    "<main><section class=\"section-card\"><div class=\"section-head\"><div><h2>Cómo usar este glosario</h2><p>La capa visible del portal emplea etiquetas más directas. Aquí se conserva también el nombre técnico original, para conectar lo visible con los CSV, los controles y el código reproducible.</p></div><div class=\"section-meta\">Ayuda de lectura</div></div>",
    interpretation_box("Si un término queda claro con su definición, su fórmula y su patrón esperado, el glosario está cumpliendo su función.", "Si aun después de leer esta página un término sigue siendo opaco, ese contenido debe seguir mejorándose."),
    table_note("El glosario no modifica los nombres técnicos de las descargas. Solo agrega una capa de interpretación para facilitar la lectura del portal."),
    "</section>",
    glossary_sections_html,
    "<p class=\"footer-note\">Glosario generado junto con el portal principal. Los nombres técnicos originales se conservan en CSV y tablas técnicas para mantener auditabilidad.</p></main>",
    "<script src=\"assets/portal.js\"></script></body></html>"
  )
  wtxt(file.path(portal_dir, "glosario_terminos.html"), glossary_page)

  save_redirect <- function(path, anchor, title) wtxt(path, c("<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\">", paste0("<title>", esc(title), "</title>"), paste0("<meta http-equiv=\"refresh\" content=\"0; url=index.html#", anchor, "\">"), "</head><body>", paste0("<p>Redirigiendo a <a href=\"index.html#", anchor, "\">", esc(title), "</a>.</p>"), "</body></html>"))
  save_redirect(file.path(portal_dir, "qc_tecnico.html"), "qc-tecnico", "QC técnico")
  save_redirect(file.path(portal_dir, "coherencia_tabla_estandar.html"), "curvas", "Coherencia de tabla estándar")
  save_redirect(file.path(portal_dir, "cola_terminal_110plus.html"), "cola-terminal", "Cola terminal y 110+")

  pdf_page <- function(title, subtitle = NULL) { grid.newpage(); grid.text(title, x = .05, y = .94, just = c("left", "top"), gp = gpar(fontsize = 18, fontface = "bold")); if (!is.null(subtitle)) grid.text(subtitle, x = .05, y = .885, just = c("left", "top"), gp = gpar(fontsize = 10, col = "grey30")) }
  pdf_table <- function(dt, title, n = 15) { grid.newpage(); grid.text(title, x = .05, y = .95, just = c("left", "top"), gp = gpar(fontsize = 14, fontface = "bold")); grid.text(if (nrow(dt)) paste(capture.output(print(head(dt, n))), collapse = "\n") else "Sin registros.", x = .05, y = .89, just = c("left", "top"), gp = gpar(fontsize = 7.1, fontfamily = "mono")) }
  index_pdf <- file.path(tomo_dir, "indice_de_tomos_standard_life_table.pdf")
  pdf(index_pdf, width = 11, height = 8.5, onefile = TRUE); pdf_page("Índice de tomos - tabla de vida estándar", "El portal principal es una sola página. Los tomos quedan como evidencia estática."); grid.text(paste(c("1. tomo_qc_resumen_standard_life_table.pdf", paste0(seq_len(nrow(meta)) + 1L, ". tomo_coherencia_", slug(meta$standard_source), "_", slug(meta$standard_version), ".pdf")), collapse = "\n"), x = .08, y = .78, just = c("left", "top"), gp = gpar(fontsize = 10, fontfamily = "mono")); dev.off()
  qc_pdf <- file.path(tomo_dir, "tomo_qc_resumen_standard_life_table.pdf")
  pdf(qc_pdf, width = 11, height = 8.5, onefile = TRUE); pdf_page("Tomo QC resumen - tabla de vida estándar", "Primero estado, luego evidencia resumida."); pdf_table(qc_summary[, .(dataset, check_name, status, n_rows)], "Resumen QC", 20); pdf_table(knot_summary, "Resumen de knots", 10); pdf_table(terminal_summary, "Resumen terminal", 12); dev.off()
  tomo_manifest <- data.table(tome_type = c("index", "qc_summary"), standard_source = NA_character_, standard_version = NA_character_, path = c(rel(index_pdf), rel(qc_pdf)))
  for (i in seq_len(nrow(meta))) {
    z <- meta[i]
    tpath <- file.path(tomo_dir, paste0("tomo_coherencia_", slug(z$standard_source), "_", slug(z$standard_version), ".pdf"))
    pdf(tpath, width = 11, height = 8.5, onefile = TRUE)
    pdf_page(paste0("Coherencia - ", z$standard_source, " / ", z$standard_version), "Edad simple en eje X. Cuando hay varios sexos, primero se comparan juntos.")
    pr <- plot_manifest[standard_source == z$standard_source & standard_version == z$standard_version]
    for (j in seq_len(nrow(pr))) for (img in c(pr$curve_png[j], pr$delta_png[j], pr$knots_png[j])) { grid.newpage(); grid.raster(png::readPNG(file.path(portal_dir, img)), width = unit(1, "npc"), height = unit(1, "npc")) }
    pdf_table(delta[standard_source == z$standard_source & standard_version == z$standard_version & !is.na(delta_ex)][order(-abs_delta_ex), .(sex_source_value, exact_age, age_band, ex, delta_ex, abs_delta_ex)], "Top cambios por edad simple", 18)
    dev.off()
    tomo_manifest <- rbind(tomo_manifest, data.table(tome_type = "coherence", standard_source = z$standard_source, standard_version = z$standard_version, path = rel(tpath)), fill = TRUE)
  }
  fwrite(tomo_manifest, file.path(download_dir, "tomo_manifest.csv"))

  artifacts <- unique(c(
    file.path(portal_dir, c("index.html", "glosario_terminos.html", "qc_tecnico.html", "coherencia_tabla_estandar.html", "cola_terminal_110plus.html")),
    file.path(asset_dir, c("portal.css", "portal.js", "portal_data.js")),
    list.files(plotly_dir, full.names = TRUE, recursive = TRUE),
    file.path(download_dir, c("selection_manifest.csv", "panel_summary.csv", "interactive_plot_manifest.csv", "catalog_profile_manifest.csv", "terminal_plot_manifest.csv", "catalog_delta_summary.csv", "summary_single_age_by_standard_sex.csv", "summary_abridged_by_standard_sex.csv", "knot_single_age_vs_abridged_comparison.csv", "ranking_largest_single_age_delta_ex.csv", "qc_input_files_manifest.csv", "single_age_tail_selected_methods.csv", "qc_standard_life_table_terminal_summary.csv", "single_age_tail_method_summary.csv", "glosario_terminos_portal.csv", "tomo_manifest.csv")),
    index_pdf, qc_pdf,
    file.path(portal_dir, plot_manifest$curve_png), file.path(portal_dir, plot_manifest$delta_png), file.path(portal_dir, plot_manifest$knots_png),
    file.path(portal_dir, terminal_plot_manifest$curve_png), file.path(portal_dir, terminal_plot_manifest$delta_png), file.path(portal_dir, terminal_plot_manifest$curvature_png),
    file.path(portal_dir, unlist(lapply(portal_data$catalog, `[[`, "profile_png"))),
    file.path(portal_dir, tomo_manifest[tome_type == "coherence", path])
  ))
  artifacts <- artifacts[file.exists(artifacts)]
  for (f in artifacts) register_artifact("standard_life_table", "qc_standard_life_table_portal", "standard_life_table_portal_v4", run_id, if (tools::file_ext(f) %in% c("html", "pdf")) "report" else "qc", f, notes = "Portal integrado y artefactos no contractuales de tabla de vida estándar.")

  register_run_finish(run_id, "success", paste("Portal generado en", normalizePath(portal_dir, winslash = "/", mustWork = FALSE)))
  message("Portal generado: ", normalizePath(file.path(portal_dir, "index.html"), winslash = "/", mustWork = FALSE))
}, error = fail_run)


