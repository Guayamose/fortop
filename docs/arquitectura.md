# Arquitectura de Fortop

[← Documentación](README.md) · [Desarrollo](desarrollo.md) · [Operación](operacion.md)

**Un monolito modular Rails, con web y worker separados, PostgreSQL y dos integraciones principales: GitHub y Gemini.** Los diagramas describen la implementación del repositorio, incluidos los dos verticales.

## C4 · Nivel 1 · Contexto

```mermaid
flowchart LR
    U["Usuario autorizado<br/>Gestiona marcas y repositorios"]
    A["Administrador<br/>Gestiona accesos y operación"]
    F["FORTOP<br/>Visibilidad y remediación SEO/GEO"]
    G["GitHub<br/>Identidad, código, issues y PRs"]
    AI["Google Gemini API<br/>Modelos y búsqueda habilitada"]
    U -->|Brief, repositorios y consultas| F
    A -->|Whitelist y controles| F
    F -->|OAuth y API de GitHub App| G
    F -->|Herramientas, investigación y respuestas| AI
    F -->|Informes, evidencias y progreso| U
```

El usuario inicia sesión con GitHub. Los permisos sobre repositorios se comprueban antes de operar. El administrador se identifica por un ID estable de GitHub; la whitelist controla quién puede acceder a la plataforma.

## C4 · Nivel 2 · Contenedores

```mermaid
flowchart TB
    Browser["Navegador<br/>HTML · Turbo · Stimulus · Tailwind"]
    GH[GitHub API]
    Gemini[Google Gemini API]
    subgraph Fortop["Sistema Fortop"]
        Web["Web Rails / Puma<br/>Sesiones, vistas, API y administración"]
        Worker["Worker Rails / Solid Queue<br/>Escaneos, estudios y documentos"]
        DB[("PostgreSQL<br/>Datos · cola · caché · cable")]
        Files["Almacenamiento persistente<br/>Documentos y adjuntos"]
        Sandbox["Docker rootless<br/>Validador de sintaxis JavaScript"]
        Web -->|Lee y escribe; encola| DB
        Worker -->|Consume cola; guarda progreso| DB
        Web -->|Sube y entrega archivos| Files
        Worker -->|Lee documentos| Files
        Worker -->|Parseo aislado| Sandbox
    end
    Browser <-->|HTTPS y progreso| Web
    Web <-->|OAuth y acceso| GH
    Worker <-->|Archivos, issues y PRs| GH
    Worker <-->|Generación y herramientas| Gemini
```

Web y worker ejecutan **la misma imagen de Rails** con roles distintos. Solid Queue usa PostgreSQL, sin Redis. `fortop_github_app/` contiene manifiesto y utilidades de registro; los callbacks se ejecutan en Rails.

## C4 · Nivel 3 · Componentes del worker

```mermaid
flowchart TB
    Queue[Trabajos de Solid Queue]
    subgraph Code["Repositorios"]
        Scan[Scans::Pipeline] --> Runner[Agents::Runner]
        Runner --> Tools[AnalysisTools / RemediationTools]
        Tools --> Workspace[Workspace y archivos originales]
        Scan --> Validator[Scans::Validator]
        Validator --> Publish[Publicación GitHub]
    end
    subgraph Brand["Visibilidad"]
        Study[Visibility::Pipeline] --> Panel[QuestionPanel e investigación]
        Study --> Extract[Extraction + EvidenceText]
        Extract --> Metrics[Metrics]
        Metrics --> Report[Diagnóstico y acciones]
    end
    Import[BrandImports::Processor]
    Google[Clientes de Gemini]
    Data[(Modelos y checkpoints)]
    Queue --> Scan
    Queue --> Study
    Queue --> Import
    Runner --> Google
    Panel --> Google
    Extract --> Google
    Report --> Google
    Import --> Google
    Scan --> Data
    Study --> Data
    Import --> Data
```

Los límites, cancelaciones y recuperaciones se comprueban alrededor de las tareas y llamadas. Los jobs usan persistencia y locks para coordinar trabajo; la configuración de producción procesa una ejecución simultánea por worker.

## Despliegue actual

```mermaid
flowchart TB
    Internet[Internet] -->|HTTPS| Proxy
    subgraph GCP["Google Cloud · fortop-ai-gkecke · europe-west1-b"]
        subgraph VM["Compute Engine · fortop-production · e2-medium"]
            Proxy[Kamal Proxy / TLS] --> Web[Web Rails]
            Worker[Worker Rails]
            PG[(PostgreSQL 17)]
            Disk[(Disco persistente /srv/fortop)]
            JS[Docker rootless de validación]
            Web --> PG
            Worker --> PG
            PG --> Disk
            Web --> Disk
            Worker --> Disk
            Worker --> JS
        end
        Secrets[Secret Manager] -.->|Carga durante despliegue| Web
        Secrets -.->|Carga durante despliegue| Worker
        Disk -->|Copia diaria| Backup[Cloud Storage / 14 días]
        Registry[Artifact Registry] -.->|Imagen Rails| VM
    end
```

Una sola VM aloja web, worker y base de datos. Es una configuración para el hackathon con persistencia y copias, sin alta disponibilidad. El DNS temporal depende de `sslip.io` y de la IP reservada.

## Datos y límites de confianza

| Dato o frontera | Tratamiento |
| :--- | :--- |
| Identidad y autorización | OAuth con state/PKCE; ID estable; acceso restringido por propietario |
| Tokens de usuario | Cifrados en PostgreSQL; renovación y comprobación de acceso |
| Escrituras en GitHub | Token efímero de instalación, limitado al repositorio; ramas `fortop/*` |
| Código y documentos externos | Se tratan como datos, sin autoridad para cambiar instrucciones |
| Briefs, investigación y respuestas | Active Record Encryption; versiones y evidencia persistentes |
| Documentos originales | Almacenamiento persistente; descarga autenticada por propietario |
| JavaScript analizado | Contenedor sin red, de solo lectura y con límites; sin ejecutar el proyecto |
| Credenciales de despliegue | Secret Manager; referencias en Kamal; fuera de Git |

## Mapa del código

| Área | Ubicación |
| :--- | :--- |
| Vistas, navegación e interacción | [views](../fortop_platform/app/views/) · [JavaScript](../fortop_platform/app/javascript/) |
| Identidad y GitHub App | [services/github](../fortop_platform/app/services/github/) |
| Agentes y ejecución de código | [services/agents](../fortop_platform/app/services/agents/) · [services/scans](../fortop_platform/app/services/scans/) |
| Investigación y medición de marca | [services/visibility](../fortop_platform/app/services/visibility/) |
| Documentos y autocompletado | [services/brand_imports](../fortop_platform/app/services/brand_imports/) |
| Administración | [services/admin](../fortop_platform/app/services/admin/) |
| Modelo y persistencia | [models](../fortop_platform/app/models/) · [db](../fortop_platform/db/) |
| Infraestructura y despliegue | [infra/gcp](../fortop_platform/infra/gcp/) · [deploy.yml](../fortop_platform/config/deploy.yml) |
