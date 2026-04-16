# MASTERS_GOVERNANCE

## Purpose

This document defines which files are normative for execution, which files are reusable guidance, and which files are contextual or archival.

## Principle

Future analysts and agents should not have to infer project truth from overlapping narratives or patch-era artifacts.

The repository should distinguish clearly between:
1. normative operational files;
2. normative and reusable guidance files;
3. contextual or archival files.

## Normative operational files

These drive execution and validation:
- `config/`
- `R/`
- `scripts/`
- `data/final/`
- `data/derived/qc/`
- `reports/`

Current normative masters/specs:
- `config/spec_life_table_standard_abridged.yml`
- `config/spec_life_table_standard_single_age.yml`
- `config/maestro_sex_omop.csv`
- `config/pipeline_steps.csv`
- `config/pipeline_profiles.yml`
- `data/raw/standard_life_table/life_expectancy_standard_who_gbd.csv`

## Normative documentation files

These guide maintainers and agents:
- `AGENTS.md`
- `README.md`
- `README.qmd`
- `docs/PROJECT_CONTEXT.md`
- `docs/DATA_CONTRACT.md`
- `docs/RUNBOOK.md`
- `docs/MASTERS_GOVERNANCE.md`

## Reusable guidance and operating masters

These files help future work without overriding the contract or specs:
- `docs/quickstart_first_use.md`
- `docs/operations_manual.md`
- `docs/docker_manual.md`
- `maestros/README_MAESTROS.md`
- `maestros/metodologia/*`
- `maestros/continuidad/*`

## Contextual or archival files

Narrative or historical files may be kept for reference, but they should not govern execution.

Typical examples:
- `README_pipeline.md`
- `data/raw/standard_life_table/archive/*`
- temporary QC render folders under `data/derived/qc/standard_life_table/tmp_*`

## Decision rules

### Keep and migrate
Keep the information if it helps explain:
- real methodological decisions;
- output semantics;
- maintenance and debugging practice;
- how to rerun or audit the pipeline.

### Archive
Archive files whose content is historically useful but no longer belongs in the live execution path.

### Delete
Delete only files that are redundant, obsolete, and already represented elsewhere in the final reproducible structure.

## Rule for future additions

Any new master should fit one of these roles:
- execution norm;
- contract/spec;
- runbook;
- project context;
- reusable operating guide.

Avoid adding overlapping instruction files that tell slightly different stories about the same pipeline.
