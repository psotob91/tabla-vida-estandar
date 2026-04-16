# Manifiesto de version minima final para GitHub

## Objetivo

Este documento define la version minima final que debe subirse a GitHub para que cualquier analista pueda clonar el proyecto, ejecutar el pipeline desde cero y obtener los mismos resultados sin depender de decisiones manuales pasadas.

## Clasificacion de carpetas y archivos

### 1. Normativo reproducible: debe quedar en GitHub

- `AGENTS.md`
- `README.md`
- `README.qmd`
- `R/`
- `scripts/`
- `config/`
- `docs/`
- `maestros/`
- `reports/**/*.qmd`
- `reports/auditoria_tabla_vida_estandar.html`
- `reports/qc_standard_life_table/`
- `data/raw/standard_life_table/life_expectancy_standard_who_gbd.csv`
- `Dockerfile`
- `.dockerignore`
- `.gitignore`

### 2. Regenerable publicable: puede versionarse como producto final

- `reports/qc_standard_life_table/index.html`
- assets locales del portal
- redirects HTML de compatibilidad
- `reports/qc_standard_life_table/tomos/*.pdf`
- `reports/qc_standard_life_table/downloads/*.csv`

Se mantienen porque forman parte de la interfaz final publicable del proyecto y pueden regenerarse con el pipeline.

### 3. Regenerable no necesario en Git: no debe subirse

- `data/final/`
- `data/derived/`
- `outputs/`
- caches de Quarto
- renders intermedios
- snapshots locales de baseline

Estos artefactos se regeneran localmente y no son necesarios para entender ni operar el repo.

### 4. Legacy, humano-ad hoc o irreproducible: debe eliminarse del diseño final

- archivos creados para exploracion puntual o debugging que no se regeneran con el pipeline final
- narrativa historica redundante ya absorbida por `docs/`
- guias internas de UX o notas editoriales que no gobiernan ejecucion ni continuidad metodologica
- cualquier archivo cuyo valor dependa de decisiones manuales no codificadas

## Regla operativa

Si un archivo no entra al menos en una de estas tres funciones, no debe quedar en el repo final:

1. ejecutar el pipeline
2. entender o auditar el metodo
3. permitir continuidad con una persona analista o con un agente

## Decision actual

La version minima final para GitHub conservara:

- codigo fuente y configuracion final
- documentacion operativa y contractual
- maestros de continuidad
- fuente raw publica
- portal final y reporte metodologico publicables

No conservara:

- outputs finales tabulares regenerables
- staging y QC locales regenerables
- caches y artefactos temporales
