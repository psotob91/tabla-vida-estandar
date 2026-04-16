# RUNBOOK

## Goal

This document explains how to execute, validate, clean, and debug the final reproducible pipeline.

## Entry points

The recommended entry points are:
- `scripts/run_preflight_checks.R`
- `scripts/clean_regenerable_outputs.R`
- `scripts/run_pipeline.R`
- `scripts/compare_contract_baseline.R`

Individual build scripts remain available for debugging, but the normal workflow should go through the orchestrator.

## Canonical pipeline order

Current canonical execution order:

1. `scripts/setup_packages.R`
2. `scripts/build_standard_life_table_abridged.R`
3. `scripts/build_standard_life_table_single_age.R`
4. `scripts/qc_standard_life_table.R`
5. `scripts/export_standard_life_table_final.R`
6. `scripts/render_audit_report.R`
7. `scripts/build_terminal_module.R`
8. `scripts/build_standard_life_table_portal.R`

This execution catalog is also defined in:
- `config/pipeline_steps.csv`
- `config/pipeline_profiles.yml`

## Pre-run checks

Before running:
- confirm working directory is repository root;
- confirm required packages are installed;
- confirm raw source file exists in the expected raw folder;
- confirm config masters and YAML specs are present;
- confirm write permissions for staging, final, QC, and reports folders;
- confirm Quarto and TinyTeX or another LaTeX engine are available if reports or PDFs will be rendered.

## Baseline before changes

Before modifying contractual code:
1. identify all contractual final outputs;
2. save copies or snapshots;
3. record:
   - schema
   - types
   - row count
   - key uniqueness
   - basic ranges
   - checksum/fingerprint where useful

## Standard execution

### Fast path

```bash
Rscript scripts/run_preflight_checks.R
Rscript scripts/run_pipeline.R --profile full
```

### Clean rebuild from scratch

```bash
Rscript scripts/run_preflight_checks.R
Rscript scripts/run_pipeline.R --profile full --clean-first
```

### Useful partial profiles

Core data build only:

```bash
Rscript scripts/run_pipeline.R --profile core
```

Reports only, assuming core outputs already exist:

```bash
Rscript scripts/run_pipeline.R --profile reports
```

## Cleaning regenerable outputs

Dry run:

```bash
Rscript scripts/clean_regenerable_outputs.R
```

Confirmed cleanup:

```bash
CLEAN_DRY_RUN=false CLEAN_CONFIRM=YES Rscript scripts/clean_regenerable_outputs.R
```

This script is allowed to clear regenerable outputs under:
- `data/final/`
- `data/derived/`
- `data/_catalog/`
- `outputs/`
- rendered artifacts under `reports/`

It must not remove:
- `data/raw/`
- `config/`
- `R/`
- `scripts/`
- source `.qmd` files
- docs and masters

## Post-run validation

After running:
- verify all contractual outputs exist;
- verify schema and types;
- verify QC outputs were generated;
- compare post-run outputs against baseline if this was a refactor or contract change;
- verify report rendering;
- inspect the terminal-tail diagnostics and plots.

For audit tasks, pass the pre-change baseline directory explicitly:

```bash
Rscript scripts/compare_contract_baseline.R data/derived/qc/standard_life_table/baseline_contract_YYYYMMDD_HHMMSS
```

## Reports and web outputs

Audit report source:
- `reports/auditoria_tabla_vida_estandar.qmd`

Audit report output:
- `reports/auditoria_tabla_vida_estandar.html`

Main web outputs:
- `reports/qc_standard_life_table/index.html`
- `reports/qc_standard_life_table/qc_tecnico.html` (redirect de compatibilidad)
- `reports/qc_standard_life_table/coherencia_tabla_estandar.html` (redirect de compatibilidad)
- `reports/qc_standard_life_table/cola_terminal_110plus.html` (redirect de compatibilidad)

Main PDF outputs:
- `reports/qc_standard_life_table/tomos/indice_de_tomos_standard_life_table.pdf`
- `reports/qc_standard_life_table/tomos/tomo_qc_resumen_standard_life_table.pdf`
- `reports/qc_standard_life_table/tomos/tomo_coherencia_*.pdf`

The terminal module must explain explicitly:
- that `85+` is open in the raw source;
- that `age_end = 120` is source coding, not proof of a closed observed interval;
- that the contractual final output keeps `110+` as the final open interval;
- that `ex(110+)` is positive and derived from internal support through age `125`;
- that post-85 shapes are modeled rather than directly observed;
- that method comparisons are audit artifacts, not separate contractual datasets.

## Debugging priorities

If execution fails, debug in this order:
1. file paths
2. raw input availability
3. package and dependency issues
4. normalization logic
5. single-age and terminal-tail construction
6. spec mismatches
7. QC/report rendering issues

## Docker route

Docker is part of the supported operating model. See:
- `Dockerfile`
- `docs/docker_manual.md`

The Docker route should reproduce the same outputs as the local route.

## Minimum evidence for completion of an audit or refactor task

A task is not complete unless it includes:
- summary of files changed;
- confirmation that contractual outputs still exist;
- baseline vs post-change comparison;
- QC status;
- report rendering status.
