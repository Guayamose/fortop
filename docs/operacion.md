# Administrar y operar Fortop

[← Documentación](README.md) · [Arquitectura](arquitectura.md)

## Entorno desplegado

| Recurso | Configuración |
| :--- | :--- |
| Aplicación | https://fortop.34-76-10-0.sslip.io |
| Proyecto Google Cloud | `fortop-ai-gkecke` |
| VM / zona | `fortop-production` / `europe-west1-b` |
| Cómputo | `e2-medium`; web y worker en contenedores separados |
| Datos | PostgreSQL 17 y archivos en `/srv/fortop` |
| Copias | `gs://fortop-ai-gkecke-backups`, ciclo de vida de 14 días |
| Despliegue | Kamal, imagen en Artifact Registry, secretos en Secret Manager |

La fuente de configuración es [config.json](../fortop_platform/infra/gcp/config.json); [production.json](../fortop_platform/infra/gcp/production.json) conserva los identificadores públicos del entorno. La IP está reservada. El dominio temporal depende de `sslip.io`.

## Administración y acceso

El panel **`/admin`** aparece en el menú de cuenta. Solo administra la cuenta con GitHub ID **63518682**, identificada como `@Guayamose`. El ID estable, no el nombre ni el correo, determina ese privilegio.

| Sección | Gestión |
| :--- | :--- |
| Accesos | Whitelist de cuentas personales verificadas contra GitHub |
| Usuarios | Datos, consumo y acceso de cada cuenta |
| Repositorios y marcas | Proyectos y ejecuciones asociadas |
| Actividad | Pausa, continuación, cancelación y recuperación |
| Configuración | Nuevas ejecuciones, modelos y límites operativos |
| Auditoría | Registro de acciones administrativas |

Retirar una autorización bloquea las sesiones en su siguiente petición, conservando los datos. Las ejecuciones ya iniciadas deben gestionarse desde Actividad si también quieres detenerlas. El administrador está exento de whitelist, pero sus rutas normales siguen limitadas a sus propios proyectos.

Para eliminar una cuenta o proyecto, termina o cancela primero sus trabajos, incluidos los pausados. Estas eliminaciones no borran issues ni PRs ya publicados en GitHub.

## Configuración y coste

Los ajustes guardados en PostgreSQL tienen prioridad sobre las variables de entorno. Restablecerlos recupera los valores del entorno y sus predeterminados. Las credenciales permanecen fuera del panel.

| Control | Valor predeterminado | Aplicación |
| :--- | :--- | :--- |
| Modelo | `gemini-3.5-flash-lite` | Nuevos trabajos de código, documentos y visibilidad |
| Presupuesto de un estudio | US$ 3; máximo configurable por estudio US$ 50 | Se guarda al crear el estudio |
| Presupuesto diario | US$ 10 por usuario | Compartido entre estudios y documentos; día de Europe/Madrid |
| Solicitudes por estudio | 1500 | Tope positivo; no admite cero |
| Tokens por estudio | 2.000.000 | Tope positivo; no admite cero |
| Tokens de repositorios | `0`, sin límite acumulado | Puede fijarse un presupuesto explícito |
| Worker | Una ejecución simultánea | `JOB_CONCURRENCY=1` en producción |

En visibilidad se reserva gasto antes de llamar a Google y se reconcilia con el uso devuelto. Si el presupuesto no alcanza, se pausa antes de la siguiente petición. Una respuesta perdida conserva la reserva porque podría haberse facturado. Las tarifas se guardan en cada estudio y están definidas en [Visibility::Settings](../fortop_platform/app/services/visibility/settings.rb).

El coste mostrado es **una estimación**, no un máximo garantizado de factura: las consultas internas de búsqueda pueden superar la reserva. Los repositorios registran tokens, sin incorporarlos al presupuesto monetario de visibilidad. Cambiar un modelo exige revisar sus tarifas y compatibilidad; los estudios existentes conservan su configuración.

**Pausar nuevas ejecuciones** bloquea inicios, continuaciones y reintentos, también para el administrador. No interrumpe peticiones en curso.

## Recuperar una ejecución

| Caso | Acción |
| :--- | :--- |
| Fallo transitorio de GitHub al publicar | Hasta tres intentos automáticos; después, **Reintentar publicación** |
| Publicación con correcciones guardadas | Reutiliza y valida el parche; no vuelve a llamar a los agentes |
| Fallo de escaneo anterior al checkpoint | **Reintentar análisis** inicia otro trabajo con IA |
| Estudio pausado o fallido | Continuar/recuperar reutiliza las tareas completadas |
| Nuevo estudio o reinicio | Recoge respuestas nuevas y vuelve a consumir IA |
| Ejecución sin actividad durante 30 minutos | Se marca el fallo y se habilita recuperación |

Los errores de permisos o validación requieren corregir la causa. En visibilidad, los fallos transitorios tienen hasta tres intentos por tarea; los locks de PostgreSQL protegen frente a trabajos duplicados.

### Revalidar evidencia ya guardada

Para corregir la interpretación de citas sin volver a consultar Google, el servicio de mantenimiento permite una simulación:

```ruby
study = VisibilityStudy.find(id_del_estudio)
Visibility::RevalidateEvidence.new(study).call
```

Tras revisar el resultado, `call(apply: true)` persiste la revalidación. Requiere un estudio detenido y sin diagnóstico final; conserva su estado y no encola trabajos ni altera el consumo. La versión de evidencia interviene en la comparación histórica.

## Documentos de marca

Se admiten PDF con texto, DOCX, PPTX, TXT, Markdown, CSV y JSON: hasta **10 archivos**, **20 MB por archivo**, **50 MB y 300.000 caracteres en total**. `pdftotext` debe estar disponible para PDF.

La extracción es local y Gemini propone el formulario sin búsqueda. Las ediciones del usuario durante la lectura se respetan. Originales y texto quedan asociados al brief y cada estudio conserva su selección. El texto extraído y el resultado de importación se cifran en PostgreSQL; las descargas exigen sesión del propietario. El reintento de una importación fallida lo solicita el usuario.

## Desplegar una versión

Desde `fortop_platform/`, con Google Cloud CLI, Docker, SSH por IAP y acceso al proyecto:

1. Guarda la versión en Git y comprueba la CI.
2. Pausa nuevas ejecuciones desde Administración. Pausa los trabajos activos y espera a que terminen las importaciones de documentos.
3. Ejecuta `bin/deploy`.
4. Comprueba `/up`, login, web y worker; restaura el estado anterior de nuevas ejecuciones y continúa los trabajos que corresponda.

`bin/deploy` carga los secretos en memoria desde Secret Manager y utiliza un token temporal para Artifact Registry. `.kamal/secrets` solo contiene referencias a variables. El wrapper exige el proyecto Fortop; no vuelques los secretos a terminal o archivos versionados.

Comprobación del worker, sin IA ni publicaciones en GitHub:

```sh
bin/deploy app exec --roles worker --reuse 'bin/rails runner infra/gcp/check_production.rb'
```

El script verifica conexiones, almacenamiento, aislamiento del validador y entrega de un trabajo. Una parada forzada puede interrumpir trabajo sin checkpoint; el despliegue no sustituye la pausa previa.

<details>
<summary><strong>Preparación inicial de la infraestructura</strong></summary>

Estos pasos son para provisionar el entorno; no se repiten en cada actualización:

```sh
ruby infra/gcp/provision.rb
bin/rails runner infra/gcp/prepare_secrets.rb
bin/rails runner infra/gcp/production_key.rb
bin/rails runner infra/gcp/verify_credentials.rb
bin/deploy setup
```

El aprovisionamiento conserva recursos existentes. Los secretos iniciales se crean una vez; no se regeneran claves de cifrado ni contraseñas de una producción existente. La clave de producción está asociada al proyecto Fortop y restringida a Generative Language API.

En la GitHub App registra el origen público, `/auth/github/callback` y `/github/installations/callback`. Puedes conservar el callback de localhost. `/setup/github` permanece cerrado en producción.

</details>

## Copias y restauración

Un timer copia diariamente las cuatro bases —principal, cola, caché y cable— y los documentos. El bucket bloquea acceso público. La cuenta de la VM puede crear y leer copias, sin borrarlas ni sobrescribirlas. El disco de datos no se borra al eliminar la VM.

Para lanzar una copia y consultar su resultado, ejecuta **en la VM**:

```sh
sudo systemctl start fortop-backup.service
sudo journalctl -u fortop-backup.service
```

El log identifica la marca UTC del archivo. Para verificarlo, desde `fortop_platform/`, sustituye `MARCA_UTC` por esa marca:

```sh
gcloud compute ssh fortop-production \
  --project=fortop-ai-gkecke --zone=europe-west1-b \
  --tunnel-through-iap \
  --command='sudo bash -s -- gs://fortop-ai-gkecke-backups/MARCA_UTC/fortop.tar' \
  < infra/gcp/verify_backup.sh
```

La comprobación restaura cada base en una base temporal, valida tablas y el archivo de documentos y limpia la prueba. **No reemplaza los datos de producción.** Una recuperación real exige seleccionar la copia, detener escrituras, restaurar bases y archivos y conservar las mismas claves de descifrado de Secret Manager. No hay un comando automatizado de restauración sobre producción.

## Límites del despliegue

Web, worker y PostgreSQL comparten una VM; una caída afecta a los tres. Las copias permiten recuperación, pero no proporcionan alta disponibilidad. El validador JavaScript usa un Docker rootless separado y solo el worker recibe su socket; la aplicación no recibe el socket Docker administrador del host.
