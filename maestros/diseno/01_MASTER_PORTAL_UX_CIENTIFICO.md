# MASTER_PORTAL_UX_CIENTIFICO

## Propósito

Este maestro define el estándar reusable para portales documentales de proyectos analíticos, epidemiológicos y metodológicos. Su objetivo es combinar lectura clara, formalidad y auditabilidad sin dejar rastros de redacción mecánica ni exceso de jerga.

## Jerarquía de lectura

El portal debe organizarse como una secuencia clara:

1. encabezado y acciones rápidas;
2. acceso visible al anexo metodológico;
3. estado general;
4. lectura sustantiva de resultados;
5. glosario y ayudas;
6. descargas y operación.

En el hero deben aparecer solo los mensajes que realmente orientan la lectura principal. Las propiedades metodológicas secundarias no deben presentarse como badges llamativos si interrumpen la jerarquía visual.

## Capa visible vs capa técnica

- **Visible**: etiquetas humanizadas, definición breve, interpretación, patrón esperado y señal de alerta.
- **Tooltip**: nombre técnico, explicación resumida y enlace al anexo cuando haga falta.
- **Descarga o tabla técnica**: nombres originales y detalle completo para auditabilidad.

## Reglas de lenguaje

- Preferir español claro en la capa visible.
- Mantener tildes, ñ y puntuación completa.
- Mantener inglés técnico solo si es realmente jerga consolidada.
- Si un término se conserva en inglés, debe llevar ayuda contextual.

Reemplazos recomendados:

- `Lectura tranquilizadora` -> `Patrón esperado`
- `Señal para revisar` -> `Señal de alerta`
- `Cómo interpretar este bloque` -> `Interpretación`

## Tooltips

Todo término técnico potencialmente opaco debe tener:

- ícono `i` circular discreto;
- definición corta;
- utilidad del término;
- patrón esperado o señal de alerta cuando aplique;
- enlace al anexo metodológico si requiere desarrollo largo.

## Tablas

- La tabla visible debe ser un resumen, no un vertedero de columnas.
- El detalle técnico debe ir en bloque plegable o descarga.
- El portal no debe duplicar, sin necesidad, la evidencia tabular que el anexo científico ya resume mejor.

## Figuras y enlaces

- El portal debe enlazar al anexo metodológico cuando la explicación breve no alcance.
- Las figuras o gráficos que queden pequeños deben poder ampliarse o estar acompañados de una ruta clara al anexo o a la descarga.
- Cuando una evidencia tabular ya se explica mejor en el anexo, el portal debe resumir y remitir, no duplicar.
- Las notas metodológicas generales deben integrarse en el subtítulo o en el bloque contextual correspondiente; no deben convertirse por defecto en chips o cintillos de alto contraste.
- La terminología del portal debe quedar alineada con el anexo final; si el anexo cambia nombres de secciones o conceptos, los tooltips y enlaces del portal deben actualizarse.

## Consistencia editorial

Antes de cerrar un portal, revisar de forma exhaustiva:

- inglés innecesario;
- siglas sin contexto;
- frases informales;
- frases con tono promocional;
- repeticiones formulaicas;
- expresiones que delaten redacción de IA.

## Criterio final

El portal debe parecer escrito por un equipo técnico cuidadoso, no por una demo de producto ni por un asistente automático.
