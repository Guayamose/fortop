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

El vertical de repositorios funciona en desarrollo local. El diagnóstico de
visibilidad de marca en respuestas de IA está previsto y todavía no está
implementado. Las plantillas de despliegue no representan un entorno de
producción activo.

El repositorio sigue [Gitflow](docs/GIT_WORKFLOW.md), con `main`, `develop`,
ramas de funcionalidad, releases y etiquetas de versión. El
[historial de versiones](CHANGELOG.md) recoge el alcance de cada entrega.
