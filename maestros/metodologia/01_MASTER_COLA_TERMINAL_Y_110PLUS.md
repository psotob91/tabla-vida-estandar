# Cola terminal y 110+

## Regla metodologica vigente

- `85+` viene de la fuente abridged como intervalo abierto
- `age_end = 120` se interpreta como codificacion del abierto
- el contractual final no fuerza `ex(110+) = 0`
- la cola interna se modela hasta `125`
- el contractual exporta `110+` como ultimo intervalo abierto

## Trabajo esperado

- revisar `84-85-86`
- revisar monotonicidad en estandares donde corresponde
- revisar si el delta post-85 parece artefacto de cierre
- comparar el metodo final con el benchmark ex-space

## Si hay que cambiar algo

Primero:

1. guardar baseline
2. correr benchmark
3. revisar QC y portal
4. documentar el cambio real
