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

# ---------------------------------------------------------------------------
# cep_run_id(): identificador de corrida, reproducible si se pide.
#
# Por que existe: el `format(Sys.time(), ...)` que habia en 28 sitios de cuatro
# repos era la UNICA razon por la que dos corridas del mismo commit no producian
# ficheros byte a byte identicos. `tabla-mortalidad-peru` no lo usaba, y por eso
# era el unico repo que si lo era. La huella de orchestration/baseline.sh tiene
# que ignorar columnas volatiles justamente por esto.
#
# Comportamiento: si CEP_RUN_ID esta definida, se usa tal cual (run_dag.sh la
# deriva del commit del repo, no del reloj). Si no, se conserva exactamente el
# comportamiento anterior. Es decir: fuera del DAG nada cambia.
# ---------------------------------------------------------------------------
cep_run_id <- function(prefijo = "", formato = "%Y%m%d_%H%M%S") {
  fijo <- Sys.getenv("CEP_RUN_ID", "")
  if (nzchar(fijo)) return(paste0(prefijo, fijo))
  paste0(prefijo, format(Sys.time(), formato))
}

# ---------------------------------------------------------------------------
# cep_created_at(): sello temporal del dato, reproducible si se pide.
#
# Por que existe: tras hacer determinista run_id quedaban 2 ficheros distintos
# byte a byte en pre y 5 en post, AL MISMO COMMIT. La causa era esta columna:
# un reloj de pared dentro del dato. orchestration/huella_estable.py ya la
# trataba como volatil (por eso el contenido salia identico), pero volatil no es
# lo mismo que reproducible.
#
# Cuando CEP_CREATED_AT esta definida se usa tal cual; run_dag.sh la deriva de la
# FECHA DEL COMMIT del repo. Eso es honesto: el sello dice cuando se fijo el
# codigo que produjo el dato, no cuando se ejecuto la maquina.
# ---------------------------------------------------------------------------
cep_created_at <- function(formato = "%Y-%m-%d %H:%M:%S") {
  fijo <- Sys.getenv("CEP_CREATED_AT", "")
  if (nzchar(fijo)) return(fijo)
  format(Sys.time(), formato)
}
