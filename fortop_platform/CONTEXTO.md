# Fortop · decisiones de producto

Estado: **22 de octubre de 2026**. [Producto](../docs/producto.md) · [Arquitectura](../docs/arquitectura.md) · [Guías](../docs/README.md)

## Qué es

Una plataforma para entender la visibilidad de una marca en respuestas generadas y mejorar la base técnica de su web. Tiene dos áreas independientes: **Repositorios** y **Visibilidad de marca**, con una página de bienvenida propia.

## Recorridos implementados

| Repositorios | Visibilidad de marca |
| :--- | :--- |
| GitHub → conectar repo → iniciar análisis | Crear marca → aportar brief o documentos → iniciar estudio |
| Agente de análisis → agente de remediación → validación | Interpretación → investigación → preguntas → respuestas → evidencia |
| Issues y PR con cambios para revisión | Informe persistente con métricas, fuentes, competencia y acciones |
| Progreso, consola, hallazgos y diffs | Progreso, consola, filtros, respuestas y evolución comparable |

Una acción técnica del informe puede enviarse explícitamente a un repositorio propio. Los agentes contrastan la recomendación con el código antes de proponer una corrección.

## Decisiones que se mantienen

- **Google Gemini como proveedor de los agentes.** Las claves de OpenAI y Anthropic están reservadas para otros usos y no se utilizan en estos recorridos.
- **Medición delimitada.** El informe observa Gemini API con búsqueda habilitada, no otros asistentes ni sus interfaces de consumo.
- **Evidencia verificable.** La detección de marca se resuelve por contexto; las citas se contrastan contra el texto visible. Los casos ambiguos no se cuentan como ausencias.
- **Control del usuario.** Pausa, continuación, cancelación, recuperación y nuevas ejecuciones. El PR requiere revisión y CI del repositorio.
- **Marca sin web obligatoria.** Los documentos pueden autocompletar el brief y permanecer como contexto; se conserva una versión por estudio.
- **Borrado desde la marca.** El propietario puede eliminarla con confirmación, junto con sus estudios. Antes debe terminar o cancelar los estudios activos o pausados. Los documentos compartidos se conservan.
- **Acceso privado.** GitHub OAuth, whitelist y administración exclusiva del ID de GitHub del propietario de Fortop.
- **Interfaz clara.** Espacio, tipografía, iconos y jerarquía; pocas cajas. La actividad de los agentes tiene un diseño común en ambos verticales.
- **Coste visible.** Repositorios registran tokens y admiten límites explícitos. Visibilidad usa presupuestos, reservas y tarifas guardadas por estudio.
- **Una base técnica común.** Monolito Rails, PostgreSQL y Solid Queue; web y worker se despliegan por separado en la misma VM de Google Cloud.
- **Git sencillo.** El trabajo se mantiene en `master`.

## Material del proyecto

La [presentación final](../fortop_pitch/README.md) está en español: 3 minutos de diapositivas y 1 minuto de demo aparte. La identidad oficial está en el [brand kit](../fortop_brand_kit/README.md).

Las láminas iniciales del hackathon se conservan en `fortop-deliverables/`. La documentación vigente de producto, arquitectura, instalación y operación está en [`docs/`](../docs/README.md); sustituye las descripciones tempranas de funciones pendientes.
