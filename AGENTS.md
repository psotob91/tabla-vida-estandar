# AGENTS.md

## Scope
This file governs the whole repository unless a deeper AGENTS.md overrides it.

## Repository purpose
This repository builds a reproducible standard life table pipeline in R, including:
- a normalized abridged standard life table;
- a single-age expanded standard life table;
- structural and epidemiologic QC outputs;
- final exports and extended dictionaries.

## Critical invariant: do not break contractual outputs
The final outputs must not be broken.

Preserve strictly:
- output paths;
- file names;
- column names;
- column types;
- row-level granularity;
- semantic meaning of fields;
- any assumptions required by downstream users.

If you identify a better design that would break compatibility, implement it only as an additional versioned output or document it as a future recommendation.

## Files to read first
Before making changes, read:
- `README.md`
- `docs/PROJECT_CONTEXT.md`
- `docs/DATA_CONTRACT.md`
- `docs/RUNBOOK.md`
- `docs/MASTERS_GOVERNANCE.md`

## Mandatory planning rule
Always use Plan before making changes.
Do not start editing until you have:
1. inspected the repository;
2. identified contractual outputs;
3. proposed a staged plan.

## Working style
- Prefer small, verifiable changes.
- Describe the real implemented method, not an idealized one.
- Be explicit about uncertainty.
- Prioritize reproducibility, auditability, and output-contract stability.
- Do not silently change statistical meaning.

## Required workflow
1. Inspect repository structure and execution flow.
2. Identify all contractual final outputs and baseline them.
3. Save pre-change fingerprints:
   - schema
   - types
   - row count
   - key uniqueness
   - basic domain/range checks
   - file checksum if possible
4. Make changes.
5. Re-run the pipeline.
6. Compare baseline vs post-change outputs.
7. Report whether compatibility was preserved.

## Validation requirements
Best effort run all relevant checks after changes:
- pipeline execution
- QC generation
- report rendering
- schema comparison
- baseline vs post-change comparison

## Documentation requirements
Keep or create:
- code comments only where they add meaning
- pseudocode sections in the report
- data dictionaries for final and important intermediate tables
- deployment/run instructions

## Preferred deliverables
- a main HTML report
- updated repo docs
- explicit baseline-vs-post comparison
- clear inventory of masters/config/specs
- recommendations separated from implemented changes

## Files and folders
Treat these as normative unless evidence shows otherwise:
- `config/`
- `R/`
- `scripts/`
- `data/final/`
- `data/derived/qc/`
- `reports/`

Treat legacy narrative files outside these docs as contextual, not normative.