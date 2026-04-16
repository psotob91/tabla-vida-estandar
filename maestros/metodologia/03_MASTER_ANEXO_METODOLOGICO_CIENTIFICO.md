# MASTER_ANEXO_METODOLOGICO_CIENTIFICO

## Propósito

Este maestro define el estándar reusable para anexos metodológicos de proyectos analíticos reproducibles. La meta es producir un documento con densidad científica suficiente para auditoría, reproducibilidad y apoyo a manuscritos, sin mezclar en exceso metodología estadística con detalles puramente operativos del repositorio.

## Estructura mínima obligatoria

1. **Resumen general**
2. **Metodología bioestadística**
3. **Arquitectura informática y reproducibilidad**
4. **Evidencia tabular y contractual**
5. **Despliegue y gobernanza**

## Contenido obligatorio de la parte bioestadística

- introducción al insumo de referencia y su justificación sustantiva;
- si corresponde, cita metodológica del organismo productor del insumo;
- explicación de por qué se requiere expansión, interpolación o modelado;
- fórmulas y definiciones operativas;
- supuestos principales;
- limitaciones y retos del insumo original;
- criterio de selección del método final;
- interpretación de patrones esperados y señales de alerta.

Cuando el proyecto use tablas de vida de referencia para carga de enfermedad, debe incluir una referencia metodológica oficial del organismo fuente y distinguir con claridad entre tabla normativa y tabla observacional.

## Contenido obligatorio de la parte informática

- arquitectura general;
- flujo reproducible del pipeline;
- relación entre tablas y artefactos;
- QC estructural;
- comparación baseline;
- outputs y diccionarios;
- entrypoints de despliegue.

## Evidencia tabular

- La web principal puede contener el detalle amplio.
- El anexo debe conservar solo las tablas realmente útiles para la lectura metodológica.
- Cuando existan salidas centrales del proyecto, conviene incluir una sección resumida en tabsets y ofrecer descargas CSV/XLSX.

## Reglas de redacción

- explicar siempre qué hace cada etapa, por qué se hace en ese punto y qué problema resuelve;
- usar conectores entre capítulos para que el lector entienda por qué una sección conduce a la siguiente;
- preferir lenguaje epidemiológico o demográfico antes que jerga interna del repositorio.
- si un capítulo depende de una idea previa importante, recordarla brevemente al inicio para sostener la continuidad de lectura.
- evitar nombres de secciones que suenen a debugging o residuos de versiones intermedias; la validación final debe leerse como estabilidad reproducible de la salida final.

## Tono y voz

- lenguaje formal, sobrio y natural;
- sin tono de tutorial ni de producto;
- sin cadencias mecánicas o texto que recuerde a un asistente;
- si el proyecto lo requiere, puede escribirse en primera persona plural o en voz impersonal, pero la elección debe ser uniforme.

## Figuras y Mermaid

- Toda figura principal debe tener caption automático y referencia cruzada.
- La figura debe citarse en el texto antes de aparecer.
- Las referencias y captions deben quedar completamente en español.
- Los diagramas mínimos esperados son:
  1. flowchart reproducible del pipeline;
  2. mapa relacional de objetos de datos.
- Son recomendados:
  3. sequence diagram;
  4. arquitectura global;
  5. flujograma bioestadístico simplificado.
- Las figuras deben priorizar legibilidad: fondos claros, texto oscuro, nodos amplios y rotulación breve.
- En figuras relacionales, cuando la comprensión dependa de las llaves, se deben mostrar PK/FK visibles dentro de la figura o en una tabla breve inmediatamente debajo.
- Las figuras arquitectónicas deben evitar paneles oscuros, fondos pesados o composiciones que compitan con el texto principal.
- Si dos figuras informáticas responden casi la misma pregunta, deben fusionarse en una sola.
- Cuando la reproducibilidad manual sea importante, el diagrama operativo principal debe mostrar archivos normativos cargados o revisados, orden de scripts y salidas por etapa dentro de una misma figura numerada.
- Si además existe un orquestador relevante, puede añadirse una figura separada para ese orquestador siempre que responda una pregunta distinta de la ruta manual general.
- Cuando los nombres de archivos o rutas sean demasiado largos para un nodo Mermaid, deben abreviarse dentro de la figura y desarrollarse en el caption o en una nota breve inmediatamente posterior.
- Si una figura técnica requiere numerar pasos, esa numeración debe escribirse como `Paso 1:` o con prefijos compactos como `P1`, no como listas `1.` dentro del nodo.
- La última pasada sobre figuras debe ser visual: captions breves, glosas largas fuera del nodo y equilibrio entre lectura embebida en página y lectura en lightbox.

## Regla de no redundancia

Si una evidencia ya vive mejor en la web, el anexo no debe duplicarla sin aportar interpretación adicional. En ese caso conviene resumirla, citar la web y conservar solo la evidencia sustantiva para el argumento metodológico.

## Validación final visible

- La verificación estructural final debe explicarse como estabilidad reproducible de la salida final.
- Evitar presentar esa sección como debugging, residuo histórico o comparación de versiones superadas.
- Si existe una referencia técnica llamada `baseline`, en la capa visible debe traducirse como referencia estable de comparación o verificación de estabilidad.

## Criterio final

El anexo debe poder leerse como suplemento metodológico de un artículo o informe técnico de alto nivel. Si parece documentación interna de desarrollo, necesita una nueva revisión editorial.
