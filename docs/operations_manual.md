# Manual de operaciones

## Para que sirve

Este manual esta pensado para una persona que quiere clonar el repo, correrlo desde cero y obtener los mismos outputs finales, QC y reportes sin tocar logica metodologica.

## Secuencia oficial

```powershell
Rscript .\scripts\run_preflight_checks.R
Rscript .\scripts\run_pipeline.R --profile full --clean-first
```

## Perfiles de corrida

- `full`: pipeline completo
- `core`: construccion y exportacion de datasets
- `reports`: reporte HTML, modulo terminal y portal

## Que hace cada entrypoint

- `scripts/setup_packages.R`: dependencias del proyecto
- `scripts/build_standard_life_table_abridged.R`: normalizacion abridged
- `scripts/build_standard_life_table_single_age.R`: single-age final y benchmark terminal
- `scripts/qc_standard_life_table.R`: QC estructural y terminal
- `scripts/export_standard_life_table_final.R`: export final y diccionarios
- `scripts/build_terminal_module.R`: graficos y HTML de cola terminal
- `scripts/build_standard_life_table_portal.R`: portal y tomos
- `scripts/render_audit_report.R`: informe HTML metodologico

## Limpieza segura

Dry-run:

```powershell
Rscript .\scripts\clean_regenerable_outputs.R
```

Limpieza real:

```powershell
$env:CLEAN_DRY_RUN=\"false\"
$env:CLEAN_CONFIRM=\"YES\"
Rscript .\scripts\clean_regenerable_outputs.R
```

## Politica terminal final

- la fuente abridged trae `85+` abierto;
- la cola interna llega hasta `125`;
- el contractual final exporta `0:109` y `110+`;
- `ex(110+)` es positiva y se deriva de la cola interna.

## Donde revisar resultados

- `data/final/standard_life_table/`
- `data/derived/qc/standard_life_table/`
- `reports/auditoria_tabla_vida_estandar.html`
- `reports/qc_standard_life_table/index.html`
