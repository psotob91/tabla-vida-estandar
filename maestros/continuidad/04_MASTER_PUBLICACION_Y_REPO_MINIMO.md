# Publicacion y repo minimo

## Principio rector

Todo archivo que quede en el repo final debe cumplir al menos una de estas funciones:

1. ejecutar el pipeline
2. documentar el contrato o el metodo real
3. permitir continuidad con una persona analista o con un agente

## Que debe quedar

- scripts finales del pipeline
- helpers en `R/`
- specs y perfiles en `config/`
- docs operativas y contractuales
- maestros de continuidad
- fuente raw publica normativa
- portal final y reporte metodologico publicables

## Que no debe quedar

- outputs tabulares regenerables
- snapshots locales temporales
- archivos de debugging puntual
- narrativa historica ya absorbida por `docs/`
- cualquier artefacto que no pueda regenerarse automaticamente

## Regla para agentes

Si un agente necesita explorar o comparar escenarios:

- puede generar artefactos locales temporales
- pero no debe dejarlos como parte del repo final salvo que pasen a ser parte del pipeline reproducible

## Antes de publicar

1. correr `run_preflight_checks.R`
2. correr `run_pipeline.R --profile full --clean-first`
3. revisar el portal final
4. correr `compare_contract_baseline.R`
5. confirmar que `.gitignore` separa bien lo versionado de lo regenerable
