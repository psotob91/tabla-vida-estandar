# Pseudocodigo del pipeline final

Este documento resume la logica de cada script que queda en la version final del repo.

## `scripts/setup_packages.R`

**Inputs:** lista de paquetes requeridos.  
**Outputs:** entorno R con dependencias disponibles.

```text
definir vector de paquetes requeridos
instalar paquetes faltantes
validar que puedan cargarse
emitir mensaje de listo
```

## `scripts/run_preflight_checks.R`

**Inputs:** estructura del repo, fuente raw, configs y scripts.  
**Outputs:** aprobacion o falla antes de mutar.

```text
verificar existencia de fuente raw normativa
verificar existencia de scripts y specs criticos
verificar que el repo tenga directorios esperados
fallar temprano si falta algun insumo normativo
```

## `scripts/build_standard_life_table_abridged.R`

**Inputs:** CSV raw publico de tabla estandar.  
**Outputs:** staging abridged armonizado.

```text
leer CSV raw
limpiar nombres de columnas
mapear source, version, sexo, edades y ex a estructura canonica
derivar ancho de intervalo
marcar intervalo abierto final por estrato
validar contra spec abridged
escribir staging abridged
registrar artefactos
```

## `scripts/build_standard_life_table_single_age.R`

**Inputs:** staging abridged, specs, parametros terminales.  
**Outputs:** staging single-age final + benchmark terminal reproducible.

```text
leer abridged armonizado
por cada estrato:
  preservar knots enteros observados
  expandir edades cerradas hasta antes del tramo abierto
  construir benchmark ex-space
  construir familias law-based para la cola avanzada
  comparar continuidad, rebote del delta, monotonicidad esperada y ex terminal
  seleccionar metodo final por estrato
  derivar contractual final 0:109 y 110+
validar ex(110+) positiva
guardar staging single-age y tablas comparativas de cola
```

## `scripts/qc_standard_life_table.R`

**Inputs:** staging abridged y single-age.  
**Outputs:** QC estructural, terminal y comparativo.

```text
leer staging abridged y single-age
ejecutar checks de estructura, tipos, llaves y rangos
ejecutar checks de preservacion de knots
ejecutar checks terminales del 110+
resumir estado por check
guardar tablas QC y PDF resumido
```

## `scripts/export_standard_life_table_final.R`

**Inputs:** staging validado y specs.  
**Outputs:** CSV/RDS contractuales y diccionarios extendidos.

```text
leer staging final
revalidar estructura contractual
escribir abridged contractual
escribir single-age contractual
construir diccionarios extendidos
escribir diccionarios en CSV y XLSX
guardar resumen de exportacion
```

## `scripts/render_audit_report.R`

**Inputs:** QMD metodologico y tablas QC/export.  
**Outputs:** HTML metodologico principal.

```text
resolver rutas y tablas de soporte
renderizar auditoria_tabla_vida_estandar.qmd
registrar HTML final como artefacto
```

## `scripts/build_terminal_module.R`

**Inputs:** resumenes terminales, metodos seleccionados y comparadores.  
**Outputs:** HTML y graficos del modulo terminal.

```text
leer resumen terminal y benchmark de metodos
generar graficos terminales por estrato
renderizar modulo HTML auxiliar
registrar archivos producidos
```

## `scripts/build_standard_life_table_portal.R`

**Inputs:** outputs finales, QC, benchmark terminal, reporte y tomos.  
**Outputs:** portal unico HTML, assets, manifiestos y tomos PDF.

```text
leer outputs contractuales y tablas QC
generar payload interactivo para Plotly
generar graficos estaticos auxiliares
armar index.html unico
crear redirects de compatibilidad
generar tomos PDF y manifiestos descargables
registrar artefactos publicables
```

## `scripts/compare_contract_baseline.R`

**Inputs:** snapshot baseline contractual + outputs actuales.  
**Outputs:** resumen de comparacion baseline vs actual.

```text
leer baseline y outputs actuales
comparar existencia, filas, columnas, clases y typeof
evaluar unicidad logica
comparar checksum cuando aplique
tratar diccionarios como artefactos con metadatos variables
guardar resumen de comparacion
```

## `scripts/clean_regenerable_outputs.R`

**Inputs:** reglas de limpieza y confirmacion explicita.  
**Outputs:** directorios regenerables limpios.

```text
definir rutas regenerables
proteger snapshots baseline_contract*
si dry-run:
  reportar que se eliminaria
si confirmed:
  borrar artefactos regenerables permitidos
  recrear estructura minima esperada
```

## `scripts/run_pipeline.R`

**Inputs:** perfil de corrida, opcion clean-first.  
**Outputs:** corrida completa orquestada y log de pipeline.

```text
leer perfil y catalogo de pasos
opcionalmente limpiar regenerables
ejecutar setup y preflight
ejecutar scripts en orden segun perfil
registrar inicio, fin, estado y duracion por paso
fallar si un paso obligatorio falla
```
