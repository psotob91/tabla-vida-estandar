# Quickstart de primer uso

## Corrida minima recomendada

```powershell
Rscript .\scripts\run_preflight_checks.R
Rscript .\scripts\run_pipeline.R --profile full --clean-first
```

## Checklist rapido

- [ ] existe `data/raw/standard_life_table/life_expectancy_standard_who_gbd.csv`
- [ ] tengo Quarto si quiero el HTML de auditoria
- [ ] tengo `pdflatex` si quiero el PDF de QC
- [ ] corro primero preflight

## Si algo falla

Revisa en este orden:

1. `data/derived/qc/run_pipeline/preflight_checks.csv`
2. `data/derived/qc/run_pipeline/pipeline_run_log.csv`
3. `data/derived/qc/standard_life_table/qc_standard_life_table_summary.csv`

## Si trabajas con agente

Haz que lea en este orden:

1. `AGENTS.md`
2. `maestros/README_MAESTROS.md`
3. `docs/operations_manual.md`
