# Flujo y contrato

- la fuente publica vive en `data/raw/standard_life_table/life_expectancy_standard_who_gbd.csv`
- la tabla abridged es contractual
- la tabla single-age final tambien es contractual
- el contrato final de `single_age` exporta `0:109` y `110+`
- `ex(110+)` es positiva
- la cola interna llega hasta `125`

No romper sin version explicita:

- rutas
- nombres
- columnas
- tipos
- granularidad
- semantica
