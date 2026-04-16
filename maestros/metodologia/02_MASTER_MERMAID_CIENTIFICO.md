# MASTER_MERMAID_CIENTIFICO

## Propósito

Este maestro define el estándar reusable para diagramas Mermaid en proyectos analíticos, epidemiológicos y metodológicos. La regla central es simple: cada diagrama debe responder una pregunta distinta. Si dos diagramas dicen esencialmente lo mismo, uno sobra.

## Set de diagramas

### Obligatorios cuando existe pipeline reproducible

1. **Flowchart reproducible del pipeline**
   - Pregunta que responde: cómo corre el proyecto desde cero.
   - Debe mostrar insumos, configuraciones, procesos, salidas finales, QC y reportes.
   - Cuando sea útil para reconstrucción manual, debe incluir numeración visible de scripts y los archivos normativos que se cargan o se revisan antes de correr.
   - Si los nombres reales de archivos son demasiado largos, deben agruparse en nodos breves y el detalle debe moverse al caption o a una nota de figura.

2. **Mapa relacional de tablas y artefactos**
   - Pregunta que responde: cómo se relacionan las tablas, comparadores, diccionarios y reportes.
   - Puede implementarse como `erDiagram` o como diagrama relacional anotado si `erDiagram` no resulta legible.

### Recomendados cuando aportan información complementaria

3. **Sequence Diagram de ejecución**
   - Pregunta que responde: en qué orden se invocan scripts y qué devuelve cada etapa.

4. **Flowchart del orquestador**
   - Pregunta que responde: cómo un script orquestador como `run_pipeline.R` lee perfiles o catálogos y ejecuta los pasos en orden.
   - Puede coexistir con el flowchart general cuando uno documenta la ruta manual y el otro la lógica interna del orquestador.
   - Si ambos conviven, el texto previo debe explicar explícitamente qué pregunta responde cada figura para evitar redundancia aparente.

5. **Vista de arquitectura global**
   - Pregunta que responde: cuáles son las capas funcionales del proyecto y qué responsabilidad cumple cada una.
   - Si esa vista repite el mismo contenido del flowchart operativo, debe fusionarse y no publicarse como figura separada.

6. **Flujograma bioestadístico simplificado**
   - Pregunta que responde: cuál fue la lógica analítica sustantiva, separada de los detalles del pipeline.

### Opcionales y normalmente no necesarios

- `classDiagram`
- `stateDiagram`
- `requirementDiagram`
- `zenuml`
- `TreeView`
- sintaxis experimental de arquitectura

## Principios editoriales

1. El diagrama debe explicar relaciones reales del proyecto, no una idealización.
2. La cantidad de nodos debe mantenerse manejable para lectura en HTML y PDF.
3. El estilo debe ser científico y discreto.
4. Toda figura Mermaid debe citarse en el texto antes de aparecer.
5. Si la figura queda pequeña para lectura cómoda, debe poder ampliarse al clic o presentarse en una composición más legible.
6. En Quarto, preferir bloques Mermaid nativos con metadatos de figura (`%%| label`, `%%| fig-cap`) en lugar de wrappers complejos.

## Reglas visuales obligatorias

- usar fondo claro o transparente;
- usar texto oscuro de alto contraste;
- evitar paneles oscuros grandes o bloques saturados de color;
- evitar figuras de arquitectura resueltas como paneles oscuros por capas;
- aumentar el tamaño de letra cuando el diagrama vaya a vivir en HTML;
- ampliar nodos antes de forzar texto pequeño;
- simplificar rótulos cuando el texto empiece a salirse del recuadro;
- preferir diagramas más limpios antes que diagramas más decorados.

## Tipos de nodo recomendados

- **Inicio o fin**: cápsula o estadio.
- **Entrada o salida**: paralelogramo.
- **Proceso**: rectángulo.
- **Decisión**: rombo.
- **Artefacto persistente o base**: cilindro o forma equivalente.

## Cuándo usar cada diagrama

### Flowchart

Usarlo para:

- orden de ejecución del pipeline;
- dependencias entre scripts;
- transformación de insumos a salidas;
- arquitectura por capas cuando no se use otra sintaxis estable.
- ejecución manual equivalente cuando se necesite mostrar qué archivos se consultan y qué scripts se corren en orden.

### Sequence Diagram

Usarlo para:

- mostrar el orden exacto de invocación;
- distinguir quién llama a quién;
- separar ejecución de transformación.

### Mapa relacional

Usarlo para:

- relaciones entre tablas;
- flujo entre salidas finales, QC y reportes;
- lectura conceptual del proyecto desde el punto de vista de objetos de datos.

Si PK/FK vuelven ilegible el diagrama, reducir entidades o complementar con una tabla breve de llaves visibles. Si la relación entre tablas depende de campos concretos, priorizar un diagrama relacional anotado con PK/FK visibles frente a un mapa abstracto de dependencias.

## Reglas de implementación en Quarto

- Citar la figura antes del bloque Mermaid.
- Usar captions automáticos y referencias cruzadas.
- Probar el HTML final; no basta con que el QMD compile.
- Si `erDiagram` compromete legibilidad, reemplazarlo por una versión relacional anotada.
- Verificar siempre que ningún texto se salga del nodo una vez renderizado el HTML final.
- Si Mermaid muestra `Unsupported markdown list`, eliminar listas, enumeraciones o rutas largas dentro del nodo y mover ese detalle al caption o a una nota explicativa.
- Evitar etiquetas de nodo que empiecen con `1.`, `2.`, `3.` cuando Mermaid esté interpretando Markdown; preferir `Paso 1:` o prefijos compactos como `P1`.
- Evitar el guion largo `—` dentro de nodos si puede combinarse con sintaxis Markdown problemática; preferir separadores simples y seguros como `:`, `|` o `-`.
- Cuando un nodo deba agrupar archivos normativos o rutas extensas, usar una etiqueta breve y plana dentro de la figura y desarrollar las rutas exactas en el caption o en una nota inmediatamente posterior.
- Después de corregir la sintaxis, hacer una pasada visual separada para revisar densidad, longitud de etiquetas y equilibrio del diagrama en HTML y lightbox.
- Si una figura se entiende mejor moviendo la glosa funcional fuera del nodo, hacerlo y conservar dentro del nodo solo la etiqueta mínima necesaria.
- Si el navegador deja el Mermaid como texto crudo, simplificar sintaxis antes de intentar adornarlo.
- Evitar etiquetas largas con demasiada puntuación o saltos de línea innecesarios, porque son una fuente común de errores de render.
- Si una figura queda visualmente pesada, reducir texto y reorganizar orientación antes de introducir más color o más cajas.

## Criterio final

El diagrama debe poder leerse como parte de un anexo científico. Si parece una pizarra de desarrollo o una nota interna de debugging, debe simplificarse y reescribirse.
