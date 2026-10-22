# Ejecutar y desarrollar

[← Documentación](README.md) · [GitHub App](../fortop_github_app/README.md)

Los comandos de esta guía se ejecutan desde **`fortop_platform/`**, salvo la clonación inicial.

## Requisitos

| Dependencia | Uso |
| :--- | :--- |
| Ruby 3.3.5 y Bundler | Aplicación Rails; versión en `.ruby-version` |
| PostgreSQL | Datos y colas; producción y CI usan PostgreSQL 17 |
| `libpq-dev`, compilador y herramientas de desarrollo | Compilar dependencias Ruby en Linux |
| `libvips` y `poppler-utils` | Imágenes y extracción de texto de PDF |
| Docker | Validación aislada de JavaScript de repositorios |
| Node y npm | Solo para regenerar/probar el resaltado de sintaxis; CI usa Node 20 |
| Chrome | Pruebas de navegador |

PostgreSQL debe estar iniciado. La configuración local usa el rol de tu usuario del sistema; ese rol necesita poder crear las bases de desarrollo y pruebas. Si usas otra conexión, configúrala en el entorno o en tu copia local de `config/database.yml`.

## 1 · Instalar

```sh
git clone git@github.com:Guayamose/fortop.git
cd fortop/fortop_platform
cp -n .env.example .env
bundle install
bin/rails db:prepare
```

Esto prepara `fortop_development` y `fortop_development_queue`. No hace falta Redis. `.env` queda excluido de Git.

## 2 · Configurar Google

Añade tu clave a `.env`:

```dotenv
GOOGLE_AI_STUDIO_API_KEY=tu_clave
GEMINI_MODEL=gemini-3.5-flash-lite
VISIBILITY_GEMINI_MODEL=gemini-3.5-flash-lite
```

También se acepta `GEMINI_API_KEY`; `GOOGLE_AI_STUDIO_API_KEY` tiene prioridad. La integración usa Gemini API directamente: no requiere Vertex AI, una clave JSON de servicio ni claves de OpenAI o Anthropic.

Los nombres de modelo anteriores son los valores del proyecto, no una selección dinámica del último modelo. Para cambiar el de visibilidad, revisa también las tarifas admitidas en [Visibility::Settings](../fortop_platform/app/services/visibility/settings.rb).

## 3 · Arrancar y registrar GitHub

```sh
bin/dev
```

Se inician Rails, Tailwind y Solid Queue. Abre **http://localhost:3000/setup/github** y completa el [registro de la GitHub App](../fortop_github_app/README.md). El callback guarda las credenciales en `.env`; nunca en la página.

**Acceso local:** Fortop aplica whitelist en todos los entornos. La cuenta administradora está fijada por `User::OWNER_GITHUB_ID` (`63518682`, Guayamose). En esta instancia, pide acceso al administrador. Para una instalación independiente, cambia deliberadamente esa constante por el ID estable de tu cuenta antes de iniciar sesión; registrar otra GitHub App no te convierte automáticamente en administrador.

Para validar correcciones JavaScript, descarga la imagen configurada:

```sh
docker pull node:24.19.0-bookworm-slim
```

Los workers locales recargan las credenciales de GitHub tras el registro. Reinicia `bin/dev` después de cambiar la clave de Google u otras variables de ejecución.

## Configuración que conviene conocer

| Ajuste | Uso |
| :--- | :--- |
| `APP_URL` | Origen de la plataforma; debe coincidir con las URLs de GitHub |
| `AGENT_*` | Turnos, herramientas, tokens y contexto de los agentes de código |
| `SCAN_NODE_IMAGE` | Imagen disponible para el validador JavaScript |
| `VISIBILITY_DAILY_BUDGET_USD` | Límite diario estimado compartido por estudios y documentos |
| `VISIBILITY_MAX_REQUESTS` / `VISIBILITY_MAX_TOKENS` | Topes positivos por estudio |

La [plantilla completa](../fortop_platform/.env.example) es el punto de partida. Los ajustes guardados en **Administración → Configuración** tienen prioridad sobre el entorno. Los estudios ya creados conservan su propia configuración.

Las claves de cifrado pueden configurarse explícitamente con `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` y `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Si no están definidas, se derivan del secreto de Rails. Conserva ese material para poder leer los datos cifrados; el despliegue usa secretos persistentes.

## Pruebas

```sh
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Los servicios externos se simulan: estas pruebas no gastan tokens ni publican en GitHub. Las de sistema usan Chrome headless; puedes configurar `CHROME_BIN` y `CHROMEDRIVER_PATH` si tu instalación lo necesita. Ejecuta las pruebas únicamente contra la base de test.

Si cambias el resaltado de sintaxis:

```sh
npm ci --ignore-scripts
npm run test:syntax
npm run build:syntax
npm audit
```

El bundle generado está versionado. Incluye en el commit los cambios de `public/syntax`, `config/syntax_languages.json` y `config/importmap.rb` que produzca la compilación.

## Flujo de trabajo

El repositorio utiliza **`master`**. Haz commits por cambios coherentes y ejecuta las verificaciones correspondientes. La [CI](../.github/workflows/ci.yml) comprueba Ruby, JavaScript, seguridad, pruebas Rails y navegador en cada push o PR a `master`.

Mantén credenciales en `.env`, y temporales, bases y capturas de prueba fuera de Git. Las imágenes seleccionadas para documentar el producto viven en `docs/assets/`. Las referencias de pitches de otros proyectos se conservan solo en local.

## Problemas habituales

| Síntoma | Revisar |
| :--- | :--- |
| Rails no conecta a PostgreSQL | Servicio iniciado, rol local y configuración de conexión |
| GitHub rechaza `redirect_uri` | `APP_URL` y callback `/auth/github/callback` registrados con el mismo origen |
| La cuenta no puede entrar | Whitelist e ID administrador, además del registro de la GitHub App |
| No aparecen repositorios | Instalación en la cuenta correcta, selección de repos y acceso vigente del usuario |
| Una tarea permanece en cola | Proceso `jobs` de `bin/dev` y base de Solid Queue |
| No se valida JavaScript | Docker disponible y `SCAN_NODE_IMAGE` descargada |
| No se lee un PDF | `pdftotext` instalado y documento con texto extraíble |

Para fallos de ejecuciones o consumo, consulta [Operación](operacion.md).
