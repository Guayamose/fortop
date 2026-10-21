# Historial de versiones

## 0.1.0 — 2026-10-21

Primera versión local del vertical de análisis y remediación de repositorios.
Esta entrega importa el trabajo acumulado en commits por funcionalidad; no
existía un historial de commits anterior. Su publicación en Git no implica un
despliegue de producción.

### Producto e integraciones

- Rails 8.1, PostgreSQL, Hotwire, Tailwind y workers Solid Queue.
- Acceso con GitHub, renovación de credenciales cifradas y autorización mediante
  tokens de instalación limitados al repositorio.
- Registro de la GitHub App mediante manifiesto y callbacks locales.
- Conexión y perfil de repositorio, inicio de ejecución, progreso persistido,
  resumen, evidencias e historial.
- Agentes de análisis y remediación con Google Gemini, herramientas iterativas,
  turnos y presupuesto de tokens compartido y limitado.
- Workspace temporal acotado, validación independiente y parseo de JavaScript
  en Docker sin red ni ejecución del código del repositorio.
- Publicación recuperable de issues y PRs en ramas `fortop/*`, pendiente de
  revisión humana y sin fusión automática.

### Documentación y entrega

- Kit de marca completo con referencias, maestros, manual y fuentes.
- Business Model Canvas con nueve bloques y plan visual de viabilidad.
- Arquitectura implementada y C4 de contexto, contenedores y componentes.
- Ocho láminas en SVG, PNG y PDF, índice visual y PDF conjunto.
- Generadores portables, dependencias fijadas y empaquetado reproducible.

### Repositorio y automatización

- Monorepo en la raíz con `main`, `develop`, ramas `feature/*` y
  `release/0.1.0`; integraciones mediante merges que conservan las ramas.
- Etiqueta anotada `v0.1.0` sobre la versión integrada en `main`.
- CI y Dependabot trasladados a la raíz y adaptados a Gitflow y a la ubicación
  de Rails en `fortop_platform/`.
- Variables locales, claves, logs, temporales, dependencias y compilados
  excluidos del historial. El ZIP local duplica artefactos versionados.

### Verificación de la versión integrada

| Comprobación | Resultado local |
| --- | --- |
| Pruebas Rails | 111 pruebas, 705 aserciones; sin fallos, errores ni omisiones. |
| Prueba de sistema en navegador | 1 prueba, 30 aserciones; sin fallos, errores ni omisiones. |
| Zeitwerk | Carga de constantes correcta. |
| RuboCop | 87 archivos, sin infracciones. |
| Brakeman | 0 errores y 0 avisos de seguridad. |
| Bundler Audit | Sin vulnerabilidades detectadas. |
| Importmap Audit | Sin vulnerabilidades detectadas. |
| Workflow de GitHub | YAML, rutas y actionlint correctos; ejecución alojada pendiente de publicar el repositorio. |
| Generadores visuales | Regeneración en carpeta temporal: SVG y PNG idénticos por SHA-256; PDF conjunto de 8 páginas y ZIP válido. |

Las pruebas automatizadas simulan Google y GitHub. Esta verificación no ejecuta
análisis facturables ni crea issues o PRs externos. Brakeman imprimió ruido de
excepciones internas rescatadas, pero terminó correctamente y sin avisos.

### Alcance pendiente

El diagnóstico de visibilidad de marca en respuestas reales de IA todavía no
está implementado. Las cifras comerciales son hipótesis de planificación. El
despliegue público, la facturación y la operación de producción quedan fuera de
esta versión; Docker y Kamal conservan plantillas de configuración.
