# Fortop Platform

**La aplicación de Fortop:** visibilidad de marca y análisis/remediación SEO/GEO de repositorios, con agentes de Google Gemini.

[Ver producto](../docs/producto.md) · [Arquitectura](../docs/arquitectura.md) · [Desarrollo](../docs/desarrollo.md) · [Operación](../docs/operacion.md)

## Arranque local

Desde esta carpeta, con Ruby **3.3.5**, Bundler y PostgreSQL disponibles:

```sh
cp -n .env.example .env
bundle install
bin/rails db:prepare
bin/dev
```

Abre **http://localhost:3000**. `bin/dev` inicia Rails, Tailwind y los workers de Solid Queue. Las colas usan PostgreSQL, sin Redis.

Completa `GOOGLE_AI_STUDIO_API_KEY` en `.env` y registra la [GitHub App](../fortop_github_app/README.md). El acceso exige whitelist también en desarrollo; consulta [la configuración del administrador](../docs/desarrollo.md). La guía incluye dependencias de documentos, imágenes, validación de JavaScript y pruebas de navegador.

## Dos recorridos, una base común

| Área | Entrada | Salida |
| :--- | :--- | :--- |
| Repositorios | Repositorio autorizado por GitHub App | Hallazgos, evidencia, diffs, issues y PRs |
| Visibilidad de marca | Brief, documentos y mercados | Informe persistente, métricas, fuentes y acciones |
| Administración | Cuenta propietaria de la plataforma | Accesos, usuarios, actividad, consumo y configuración |

Los [agentes de código](../docs/agentes.md) exploran con herramientas y validan sus cambios antes de publicarlos. El [estudio de marca](../docs/metodologia.md) recoge respuestas independientes de Gemini y verifica semánticamente las menciones con citas contrastadas.

## Encontrar el código

```text
app/
├── controllers/       Peticiones, identidad y autorización
├── models/            Datos, estados y contexto versionado
├── jobs/              Ejecución asíncrona y recuperación
├── services/
│   ├── agents/        Bucle agéntico y herramientas
│   ├── scans/         Orquestación, workspace y validación
│   ├── visibility/    Investigación, evidencia y métricas
│   ├── brand_imports/ Documentos y autocompletado del brief
│   ├── github/        OAuth, instalaciones y API
│   └── admin/         Operación de la plataforma
├── views/             Interfaz Rails / Hotwire
└── javascript/        Controladores Stimulus
infra/gcp/             Infraestructura y verificaciones de producción
test/                  Pruebas con servicios externos simulados
```

## Verificar cambios

```sh
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Las pruebas simulan Google y GitHub: no gastan tokens ni publican cambios. [Assets, dependencias y CI →](../docs/desarrollo.md)

## Configurar y desplegar

- [`.env.example`](.env.example): variables locales, sin credenciales reales.
- [`config/deploy.yml`](config/deploy.yml): web, worker, PostgreSQL y límites de contenedor.
- [`infra/gcp/production.json`](infra/gcp/production.json): identificadores públicos del entorno desplegado.
- [Operación](../docs/operacion.md): accesos, presupuestos, recuperación, despliegues y copias.

La documentación detallada vive en [`docs/`](../docs/README.md). [CONTEXTO.md](CONTEXTO.md) conserva las decisiones de producto vigentes.
