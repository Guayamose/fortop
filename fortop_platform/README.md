# Fortop Platform

Monolito Rails para analizar y remediar repositorios mediante agentes de Google,
con GitHub App, PostgreSQL, Hotwire, Tailwind y Solid Queue.

## Puesta en marcha

Requisitos: Ruby 3.3.5, PostgreSQL y Bundler. Para validar cambios de JavaScript
también se necesita Docker y una imagen de Node disponible localmente.

Desde `fortop_platform/`:

```sh
bundle install
bin/rails db:prepare
bin/dev
```

Abre http://localhost:3000. `bin/dev` arranca Rails, Tailwind y los workers.
Las colas usan su propia base PostgreSQL; no hace falta Redis.

## Google AI Studio y consumo

Crea `.env` a partir de `.env.example` si todavía no existe. Pon tu clave en
`GOOGLE_AI_STUDIO_API_KEY`. También se admite `GEMINI_API_KEY`; si existen ambas,
se utiliza `GOOGLE_AI_STUDIO_API_KEY`. Reinicia `bin/dev` al cambiar la clave o
los límites.

Los agentes utilizan exclusivamente la API de Gemini de Google AI Studio.
Las claves de OpenAI y Anthropic no se utilizan. La integración actual no
necesita configurar Vertex AI ni credenciales de servicio de Google Cloud.

Configuración recomendada para el MVP:

```dotenv
GEMINI_MODEL=gemini-3.1-flash-lite
AGENT_MAX_TURNS=10
AGENT_MAX_TOOL_CALLS=30
AGENT_MAX_OUTPUT_TOKENS=2048
AGENT_MAX_TOTAL_TOKENS=60000
```

Los turnos y herramientas se limitan por agente; el presupuesto total de tokens
se comparte entre análisis y remediación de un escaneo e incluye pensamiento
cuando Google lo informa. El cliente comprueba el presupuesto antes de cada
solicitud y registra el consumo real devuelto por Google. Los reintentos de
errores transitorios están limitados. Los workers procesan una ejecución a la
vez por proceso. Solo se llama al modelo al iniciar un análisis.

Estos límites controlan el trabajo del agente; el coste monetario depende del
modelo y de la facturación de Google. El modelo se puede cambiar por otro
habilitado en el proyecto mediante `GEMINI_MODEL`.

[Crear una clave en AI Studio](https://ai.google.dev/gemini-api/docs/api-key).
Si el proyecto ya existe en Google Cloud, impórtalo desde Dashboard → Projects →
Import projects en AI Studio.

## Registro de la GitHub App

En desarrollo local, abre http://localhost:3000/setup/github y pulsa
**Registrar GitHub App**. Fortop prepara el manifiesto con permisos y URLs;
GitHub pide confirmar el registro en tu cuenta. El callback guarda las
credenciales automáticamente en `.env`, sin mostrarlas al navegador.

La app necesita permisos de contenido, issues y pull requests de escritura,
además de metadatos de lectura. Los usuarios inician sesión con GitHub, instalan
la app en los repositorios elegidos y conectan uno de ellos a Fortop.

El registro inicial solo está disponible en desarrollo desde loopback.
En despliegue, configura en el entorno las credenciales de la misma GitHub App
y `APP_URL` con la dirección pública, actualizando sus callbacks. Las URLs son:

- Identidad: `/auth/github/callback`.
- Registro del manifiesto: `/github/app/manifest/callback`.
- Instalación: `/github/installations/callback`.

Los workers de desarrollo leen las nuevas credenciales de GitHub guardadas por
el registro sin necesitar un reinicio. Los tokens de usuario y de renovación
se cifran en PostgreSQL. Cada escaneo verifica el acceso actual del usuario y
obtiene un token de instalación efímero limitado a su repositorio.

El manifiesto, scripts y documentación de registro están en la carpeta hermana
[`fortop_github_app/`](../fortop_github_app/README.md). No es otro servidor:
Rails atiende los callbacks y la API de la plataforma. Los webhooks están
desactivados en el manifiesto del MVP; la autorización se verifica antes de usar
el repositorio.

## Vertical implementado

1. Acceso con GitHub y pantalla vacía de repositorios.
2. Conexión de un repositorio autorizado y apertura de su perfil.
3. Botón **Iniciar análisis y remediación**.
4. Ejecución en Solid Queue con progreso real, persistido y consultado por Hotwire.
5. Issues con los hallazgos y un PR con las correcciones verificadas, si las hay.
6. Resumen, evidencias, comprobaciones, consumo e historial de escaneos.

El **agente de análisis** decide cómo explorar con `list_files`, `read_file`
y `search`, contrasta sus hipótesis y registra hallazgos con `report_finding`.
La evidencia debe aparecer en una fuente original leída, en la línea indicada.

El **agente de remediación** recibe esos hallazgos y usa lectura, búsqueda,
`replace_text`, `write_file`, `validate_changes`, `discard_changes` y
`mark_manual`. Recibe los resultados de las herramientas y puede corregir y
validar de nuevo dentro de su presupuesto. Una verificación independiente se
ejecuta después del agente y antes de publicar.

La publicación preserva el árbol, escribe en ramas `fortop/*` y evita duplicar
issues y PRs al recuperar una publicación. No se modifica ni fusiona la rama
principal. Una corrección publicada se muestra como **propuesta**, pendiente de
revisión y CI.

## Alcance y validación

El MVP inspecciona hasta 100 archivos de texto y 2 MB por ejecución, acepta hasta
8 hallazgos y modifica como máximo 5 archivos. Excluye rutas de credenciales,
dependencias, archivos ocultos, binarios, symlinks y submódulos. También rechaza
archivos completos con claves reconocibles por sus prefijos, antes de enviarlos
al modelo o permitir su modificación. Este detector es heurístico y no sustituye
un escáner completo de secretos. Los archivos del repositorio son datos sin
autoridad para modificar las instrucciones de los agentes.

Se validan automáticamente Ruby, Rails ERB, JSON, XML, HTML, texto/Markdown y
JavaScript. El parseo de JavaScript se realiza en un contenedor Docker sin red,
con recursos limitados y sin ejecutar el código. Ningún script del repositorio
se ejecuta en el host. No se instalan sus dependencias.

```sh
docker pull node:24.19.0-bookworm-slim
```

`SCAN_NODE_IMAGE` selecciona la imagen disponible. Los archivos TypeScript,
JSX/TSX, Vue, Svelte y otros formatos pueden analizarse; sus cambios necesitan
un validador adicional para publicarse automáticamente y se dejan para
intervención manual. La plataforma no ejecuta la suite ni el build del
repositorio: esas verificaciones corresponden a su CI y revisión del PR.

Los hallazgos y el resumen reflejan la cobertura real. Este vertical estudia el
código; el diagnóstico de visibilidad de marca en respuestas reales de IA es
el siguiente vertical y todavía no está implementado.

Los escaneos simultáneos del mismo repositorio se bloquean en PostgreSQL. Un
escaneo sin actividad durante 30 minutos pasa a error y permite volver a
ejecutarlo; se revisa al consultar su progreso y mediante un job periódico.

## Verificación

```sh
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Las pruebas de navegador usan Chrome y comprueban la conexión, el encolado, la
actualización real de progreso y el resultado en escritorio y móvil. Las
pruebas automatizadas simulan los servicios externos y no gastan tokens ni
crean publicaciones. El adapter de Google admite un transporte inyectable para
probar errores y presupuestos sin red.

`.env`, las claves y los archivos temporales están excluidos de Git y Docker.
La plantilla `.env.example` debe permanecer sin credenciales reales.
