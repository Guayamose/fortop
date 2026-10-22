# Fortop

Plataforma de análisis y remediación técnica SEO/GEO de repositorios con agentes
de Google Gemini. El equipo conecta GitHub, inicia una ejecución, sigue el
progreso y revisa los issues y pull requests propuestos.

| Carpeta | Contenido |
| --- | --- |
| [`fortop_platform/`](fortop_platform/README.md) | Monolito Rails: web, workers, agentes y datos. |
| [`fortop_github_app/`](fortop_github_app/README.md) | Registro y configuración de la GitHub App; sus callbacks viven en Rails. |
| `fortop_brand_kit/` | Maestros, variantes, manual y fuentes de la marca. |
| `fortop-deliverables/` | Canvas, plan de negocio visual, arquitectura y diagramas C4 en SVG, PNG y PDF. |

Para arrancar y configurar credenciales, consulta la
[guía de la plataforma](fortop_platform/README.md). Los comandos Rails se ejecutan
desde `fortop_platform/`; los comandos Git, desde esta raíz o sus subdirectorios.

Los verticales de repositorios y visibilidad de marca están desplegados en
[Fortop](https://fortop.34-76-10-0.sslip.io), dentro del proyecto de Google Cloud
`fortop-ai-gkecke`. El acceso requiere GitHub y autorización del administrador.
La configuración de la GitHub App debe incluir esta dirección pública para
completar el inicio de sesión. La visibilidad se mide mediante Gemini API con
búsqueda habilitada, con informes persistentes, fuentes y acciones vinculadas a
respuestas reales. La infraestructura y su operación se describen en la guía de
la plataforma.

Todo el trabajo se mantiene en la rama `master`.
