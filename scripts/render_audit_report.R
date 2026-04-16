library(here)

report_qmd <- here("reports", "auditoria_tabla_vida_estandar.qmd")
report_html <- here("reports", "auditoria_tabla_vida_estandar.html")

if (!file.exists(report_qmd)) {
  stop("No existe el reporte fuente: ", report_qmd)
}

if (!nzchar(Sys.which("quarto"))) {
  stop("No se encontro Quarto en PATH. Instale Quarto o agreguelo al PATH para renderizar HTML.")
}

status <- system2(
  "quarto",
  args = c("render", shQuote(report_qmd), "--to", "html"),
  stdout = TRUE,
  stderr = TRUE
)

cat(paste(status, collapse = "\n"), "\n")

if (!file.exists(report_html)) {
  stop("El HTML no fue generado en la ruta esperada: ", report_html)
}

message("HTML generado: ", normalizePath(report_html, winslash = "/", mustWork = FALSE))
