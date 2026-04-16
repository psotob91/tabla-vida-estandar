# Manual Docker

## Objetivo

Esta ruta permite correr el pipeline completo en un contenedor y dejar todos los resultados dentro del repo montado.

## Build

```bash
docker build -t tabla-vida-estandar .
```

## Run

```bash
docker run --rm -v "$PWD":/project tabla-vida-estandar Rscript scripts/run_pipeline.R --profile full --clean-first
```

## Notas

- el contenedor trabaja sobre `/project`
- la fuente cruda debe estar disponible dentro del repo montado
- Quarto y las dependencias para PDF/HTML deben resolverse dentro de la imagen

## Verificacion

Despues de correr, revisa:

- `data/final/standard_life_table/`
- `data/derived/qc/standard_life_table/`
- `reports/auditoria_tabla_vida_estandar.html`
- `reports/qc_standard_life_table/index.html`
