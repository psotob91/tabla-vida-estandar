# DATA_CONTRACT

## Purpose

This document defines the contractual final outputs and the semantics that downstream users depend on.

## Contractual final outputs

### 1. Standard life table abridged

- `data/final/standard_life_table/life_table_standard_reference_abridged.csv`
- `data/final/standard_life_table/life_table_standard_reference_abridged.rds`

### 2. Standard life table single-age

- `data/final/standard_life_table/life_table_standard_reference_single_age.csv`
- `data/final/standard_life_table/life_table_standard_reference_single_age.rds`

### 3. Extended dictionaries

- `data/final/standard_life_table/life_table_standard_reference_abridged_dictionary_ext.csv`
- `data/final/standard_life_table/life_table_standard_reference_abridged_dictionary_ext.xlsx`
- `data/final/standard_life_table/life_table_standard_reference_single_age_dictionary_ext.csv`
- `data/final/standard_life_table/life_table_standard_reference_single_age_dictionary_ext.xlsx`

## Logical keys

### Abridged

- `standard_source`
- `standard_version`
- `sex_id`
- `age_start`

### Single-age

- `standard_source`
- `standard_version`
- `sex_id`
- `exact_age`

## Final single-age contract

The final `single_age` contract is now:

- exported ages `0:109`
- `110+` as the final open interval
- `exact_age = 110` marks the start of the final open interval
- `ex(110+) > 0`
- `ex(110+)` is derived from an internal modeled tail up to `125`

`age_end = 111` remains an export-field convention for the open interval representation and must not be misread as a closed observed terminal age.

## Stability requirements

The following are contractual and must stay stable unless an explicit future versioned break is declared:

- output paths
- file names
- column names
- column types
- row-level grain
- field semantics

## Validation expectations

At minimum validate:

- required columns present
- expected column types
- logical-key uniqueness
- no missing values in required fields
- valid life-table ranges
- positive `ex(110+)`
- row count and schema comparison versus baseline

## Non-contractual outputs

The following are important but non-contractual:

- staging datasets
- QC tables
- benchmark tables comparing terminal methods
- HTML/PDF reports
- portal artifacts under `reports/qc_standard_life_table/`
- pipeline logs and catalogs
