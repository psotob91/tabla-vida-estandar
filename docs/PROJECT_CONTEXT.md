# PROJECT_CONTEXT

## Purpose

`tabla-vida-estandar` is a reproducible repository that transforms a public standard life-table source into standardized analytic outputs.

Its role is to produce auditable, reusable standard life tables with consistent metadata, validation, dictionaries, and QC outputs.

## Main outputs

The repository declares two main products:
1. a normalized abridged standard life table;
2. a single-age standard life table expanded from the abridged version.

These outputs should be treated as contractual unless an explicit versioned change is introduced.

## Technical role

The repository should support:
- reproducible execution;
- structural validation through YAML or equivalent specs;
- explicit dictionaries;
- audit-friendly QC outputs;
- methodological documentation based on actual code behavior.

## Documentation rule

Documentation must prioritize:
1. what the scripts really do;
2. what the specs actually enforce;
3. what the outputs actually contain.

If README, older drafts, or narrative notes differ from the implemented code, the implemented code is the technical source of truth. Differences should be documented explicitly.

## Methodological stance

When documenting methods:
- describe the real implemented workflow;
- distinguish source data, normalized abridged outputs, and single-age expanded outputs;
- document assumptions honestly;
- document limitations honestly.

## Expected audit/refactor outcomes

A successful audit/refactor should leave:
- reproducible execution;
- clearer repo structure;
- explicit runbook;
- explicit data contract;
- useful dictionaries;
- reportable QC;
- a main HTML technical/methodological report;
- preserved compatibility of contractual outputs.