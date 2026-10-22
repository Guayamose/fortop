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

## Despliegue en Google Cloud

El entorno está definido en `infra/gcp/config.json` y su dirección real en
`infra/gcp/production.json`. Todas las operaciones fijan explícitamente el
proyecto **fortop-ai-gkecke**. La VM `fortop-production` está en
`europe-west1-b`, con web y worker separados, PostgreSQL privado y disco
persistente. La dirección temporal es https://fortop.34-76-10-0.sslip.io.
Esta dirección depende del DNS público de sslip.io y de la IP reservada;
se puede sustituir por un dominio propio actualizando también GitHub.

Preparación inicial, con tu sesión de `gcloud`:

```sh
ruby infra/gcp/provision.rb
bin/rails runner infra/gcp/prepare_secrets.rb
bin/rails runner infra/gcp/production_key.rb
bin/rails runner infra/gcp/verify_credentials.rb
```

El script de infraestructura conserva recursos existentes y genera únicamente
configuración pública. `prepare_secrets` crea los secretos iniciales una sola
vez; nunca regenera claves de cifrado ni contraseñas de una producción existente.
La clave de Gemini de producción está asociada al propio proyecto Fortop y
limitada a Generative Language API. No se reutiliza una clave de otro proyecto.
La verificación consulta metadatos y GitHub, sin generar respuestas de IA.

Las credenciales se leen de Secret Manager en memoria al ejecutar `bin/deploy`.
El registro usa un token temporal de tu sesión, sin generar claves JSON de
servicio. `.kamal/secrets` contiene únicamente referencias a variables.
No ejecutes comandos que vuelquen el contenido de los secretos a la terminal.

Después de preparar el servidor y su acceso SSH por IAP:

```sh
bin/deploy setup
```

Para siguientes versiones, guarda los cambios en Git y ejecuta `bin/deploy`.
Antes de actualizar, pausa desde Administración los análisis o estudios activos
y deja que terminen las lecturas de documentos. Después puedes continuarlos;
una parada forzada del worker puede interrumpir trabajo aún sin checkpoint.
El worker permite una ejecución simultánea y se separa del proceso web.

El validador JavaScript usa un daemon Docker **rootless** de otro usuario,
con contenedores sin red, de solo lectura y con límites de recursos. El
socket del Docker administrador no se entrega a la aplicación; la web tampoco
recibe el socket del validador.

PostgreSQL crea cuatro bases con un usuario de aplicación sin permisos de
superusuario ni de creación de roles o bases. Los datos y los documentos se
guardan en `/srv/fortop`, en un disco que no se borra al eliminar la VM.
Un timer del servidor copia diariamente las cuatro bases y los documentos a
`gs://fortop-ai-gkecke-backups`, con acceso público bloqueado y retención por
ciclo de vida de 14 días. Las claves de descifrado permanecen en Secret Manager;
se necesitan para restaurar los datos cifrados. Una única VM implica que una
caída del servidor afecta temporalmente a web, workers y base de datos.

La cuenta de servicio de la VM puede crear y leer objetos únicamente en ese
bucket; no puede borrarlos ni sobrescribir copias existentes. Para crear una
copia manual, ejecuta en la VM `sudo systemctl start fortop-backup.service`.
`sudo journalctl -u fortop-backup.service` muestra el resultado y la marca UTC
que identifica el archivo `gs://fortop-ai-gkecke-backups/<marca>/fortop.tar`.

Para comprobar una copia descargada del bucket, pasa `infra/gcp/verify_backup.sh`
por stdin a `sudo bash -s -- <URL gs:// de la copia>` mediante `gcloud compute ssh`
con `--tunnel-through-iap`. El script restaura cada base en una base temporal,
comprueba sus tablas y valida el archivo de documentos. Elimina los datos de
prueba al terminar y no reemplaza las bases de producción. La comprobación
`infra/gcp/check_production.rb`, ejecutada con `bin/rails runner` en el worker,
verifica las conexiones, almacenamiento, aislamiento de JavaScript y entrega
de una tarea sin llamadas de IA ni escrituras en GitHub.

En la [configuración de la GitHub App](https://github.com/settings/apps/fortop-app)
actualiza el Homepage URL con el origen público y registra el callback OAuth
`/auth/github/callback` y el Setup URL
`/github/installations/callback` con el origen público. Se puede conservar
el callback de localhost para desarrollo. `/setup/github` sigue cerrado en
producción. El acceso de usuarios permanece sujeto a la whitelist de Fortop.

## Administración y acceso privado

El panel está en `/admin`, también disponible desde el menú de cuenta.
Solo la cuenta de GitHub con ID **63518682** (verificada como `@Guayamose`)
es administradora. Se usa el ID devuelto por GitHub durante OAuth, nunca el
nombre, correo, ID local de la base de datos ni un parámetro del navegador.
La cuenta conserva administración y acceso aunque cambie de nombre y no necesita
una fila de autorización, semillas ni variables especiales en producción.

Fortop es de acceso cerrado en todos los entornos. En **Administración → Accesos**
añade cuentas personales por su nombre de GitHub: el servidor consulta GitHub
con tu sesión, verifica la cuenta y guarda su ID estable en PostgreSQL.
Las organizaciones y las cuentas sin autorización no pueden iniciar sesión.
Los visitantes rechazados no se guardan con sus tokens. Retirar una autorización
bloquea también las sesiones existentes en su siguiente petición, conservando
sus datos. Las ejecuciones ya iniciadas continúan hasta que terminen o se
gestionen desde **Actividad**.

El panel incluye usuarios y su consumo, repositorios, marcas, ejecuciones,
recuperación y controles de agentes, configuración operativa y un registro de
las acciones administrativas. No hay delegación de administración. Las rutas
de trabajo normales siguen limitadas al propietario, incluso para el admin.
Para eliminar cuentas o proyectos primero deben terminar o cancelarse todos
sus trabajos, incluidos los que están en pausa. Las eliminaciones afectan a
los datos de Fortop; no borran issues ni PR ya publicados en GitHub.

Los ajustes de **Configuración** se guardan en PostgreSQL y tienen prioridad
sobre las variables de entorno. Cambiar límites de repositorios afecta a los
agentes al iniciarse o recuperarse; los estudios de visibilidad conservan sus
límites, modelo y tarifas guardados. El presupuesto diario compartido entre
visibilidad y documentos se comprueba antes de cada petición. **Pausar nuevas
ejecuciones** bloquea inicios, continuaciones y reintentos para todos, incluido
el administrador; no interrumpe peticiones en curso. Restablecer configuración
recupera el entorno y los valores predeterminados.

Las credenciales permanecen en los secretos del despliegue, fuera del panel.
Las páginas autenticadas no se almacenan en caché HTTP ni en la caché de Turbo.
El panel requiere las migraciones habituales (`bin/rails db:prepare`) y una base
PostgreSQL persistente en producción, que conserva autorizaciones, ajustes y
registro entre despliegues. Los costes de visibilidad y documentos son estimaciones
y reservas, no la factura del proveedor; los repositorios solo registran tokens.

## Google AI Studio y consumo

Crea `.env` a partir de `.env.example` si todavía no existe. Pon tu clave en
`GOOGLE_AI_STUDIO_API_KEY`. También se admite `GEMINI_API_KEY`; si existen ambas,
se utiliza `GOOGLE_AI_STUDIO_API_KEY`. Reinicia `bin/dev` al cambiar la clave o
los límites.

Los agentes utilizan exclusivamente la API de Gemini de Google AI Studio.
Las claves de OpenAI y Anthropic no se utilizan. La integración actual no
necesita configurar Vertex AI ni credenciales de servicio de Google Cloud.

Configuración para repositorios grandes:

```dotenv
GEMINI_MODEL=gemini-3.5-flash-lite
AGENT_MAX_TURNS=0
AGENT_MAX_TOOL_CALLS=0
AGENT_TIMEOUT_SECONDS=0
AGENT_MAX_OUTPUT_TOKENS=16384
AGENT_MAX_TOTAL_TOKENS=0
AGENT_CONTEXT_MAX_BYTES=120000
```

Un valor `0` desactiva el límite de turnos, herramientas o duración. Si se define
un valor positivo se respeta tal cual, sin techos ocultos. El presupuesto total de tokens
se comparte entre análisis, resúmenes de contexto y remediación de un escaneo e incluye pensamiento
cuando Google lo informa. El cliente comprueba el presupuesto antes de cada
solicitud y registra el consumo real devuelto por Google. Los reintentos de
errores transitorios están limitados. Los workers procesan una ejecución a la
vez por proceso. Solo se llama al modelo al iniciar un análisis.
`AGENT_MAX_TOTAL_TOKENS=0` desactiva el presupuesto acumulado de tokens y es
el valor predeterminado. Un valor positivo permite fijar un presupuesto explícito. No es una garantía monetaria: las cuotas,
precios y límites del modelo siguen dependiendo de Google.

Para evitar reenviar indefinidamente todo el historial, el agente resume los turnos
antiguos al superar `AGENT_CONTEXT_MAX_BYTES`. Conserva intactos los dos pares recientes
de llamadas y respuestas a herramientas, incluidas las firmas de Gemini. Estos resúmenes
también cuentan en el presupuesto. La remediación procesa los hallazgos en lotes de 20,
sin limitar el número total de lotes, y conserva los cambios de los anteriores.
Si GitHub rechaza un token de instalación caducado con HTTP 401, se vuelve a
comprobar el acceso del usuario y la identidad del repositorio antes de renovarlo
y repetir esa petición una sola vez. Los errores de permisos y las escrituras
con respuesta incierta siguen su recuperación habitual, sin repetirse de forma ciega.

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

El cierre del análisis se valida contra el inventario de páginas, plantillas,
componentes web, rutas y archivos de SEO. Un resumen del modelo no termina la
ejecución mientras haya fuentes web pendientes: el agente recibe las rutas y
líneas desde las que debe continuar. Una exclusión con `defer_review` requiere
una justificación que queda visible y no se cuenta como archivo revisado.
Las búsquedas, las lecturas directas y los archivos leídos por completo se
contabilizan por separado, también después de pausar y continuar.

Los rechazos de `report_finding` quedan registrados con su motivo e identificador.
El agente debe corregirlos o descartar expresamente la hipótesis con una razón
documentada antes de terminar. Un defecto no automatizable se registra como
manual; no debe desaparecer por no poder generar una corrección segura.

El **agente de remediación** recibe esos hallazgos y usa lectura, búsqueda,
`replace_text`, `write_file`, `validate_changes`, `discard_changes` y
`mark_manual`. Recibe los resultados de las herramientas y puede corregir y
validar de nuevo dentro de su presupuesto. Una verificación independiente se
ejecuta después del agente y antes de publicar.

La publicación preserva el árbol, escribe en ramas `fortop/*` y evita duplicar
issues y PRs al recuperar una publicación. No se modifica ni fusiona la rama
principal. Una corrección publicada se muestra como **propuesta**, pendiente de
revisión y CI.

Antes de publicar se guardan cifradas las correcciones verificadas. Los fallos
transitorios de GitHub tienen hasta tres intentos de publicación, con espera
entre intentos y comprobación de los recursos ya creados. No se repiten los
agentes ni su consumo de IA. Los errores de autorización o validación detienen
el reintento automático.

Si los intentos se agotan, la pantalla ofrece **Reintentar publicación** sobre
la misma ejecución. Se recuperan las correcciones desde la base analizada y se
verifican de nuevo antes de publicarlas. Los datos de recuperación se eliminan
al completar la ejecución. Las ejecuciones antiguas o fallidas antes de guardar
correcciones ofrecen **Reintentar análisis**, que inicia otro análisis con IA.

## Alcance y validación

La ejecución no impone cupos de archivos leídos, bytes totales, hallazgos ni
archivos modificados. Los inventarios, lecturas y búsquedas se recorren por páginas;
las búsquedas permiten continuar dentro del mismo archivo cuando hay muchas coincidencias.
Si GitHub trunca el árbol recursivo se recuperan los subárboles completos, siguiendo
[su API de árboles](https://docs.github.com/en/rest/git/trees#get-a-tree).
Los originales se guardan en el espacio temporal de disco para no acumularlos en memoria.
Se admite texto UTF-8 de hasta 1 MB por archivo, compatible con el cliente de GitHub.
El presupuesto configurado puede detener una ejecución antes de cubrir todo el repositorio;
la cobertura refleja los archivos efectivamente inspeccionados. Excluye rutas de credenciales,
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
un vertical independiente disponible en la sección Visibilidad de marca.

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

## Visibilidad de marca

En `/brands`, crea una marca con nombre, web pública opcional, brief, mercados e idiomas,
aliases y competidores conocidos. No necesita conectar un repositorio. Las ediciones
del contexto generan versiones inmutables: cada estudio conserva la suya.

El formulario permite arrastrar PDF con texto, DOCX, PPTX, TXT, Markdown, CSV y JSON.
La lectura de PDF necesita `pdftotext` (`poppler-utils`, incluido en Docker). Se admiten
hasta 10 archivos de 20 MB, 50 MB y 300.000 caracteres de contexto en total. Se extrae
el texto localmente y un trabajo de Solid Queue solicita a Gemini el autocompletado,
sin búsqueda web y sin sobrescribir lo que el usuario edite durante la lectura.
Los originales y su texto quedan asociados al brief; cada estudio conserva su selección.
Se pueden consultar y descargar desde el brief original del informe. Las descargas
requieren la sesión del propietario. El texto extraído y el resultado de importación
se cifran en PostgreSQL. Las lecturas comparten el presupuesto diario de visibilidad,
reservan el gasto antes de llamar a Google y solo reintentan a petición del usuario.
Los documentos aportan contexto a interpretación, investigación y diagnóstico; nunca
se incluyen en las preguntas independientes que miden la presencia de marca.

Al iniciar un estudio se ejecutan tareas pequeñas en Solid Queue: interpretación
del negocio, investigación con Google Search, investigación específica de cada mercado,
contraste de competidores, diseño de preguntas, respuestas independientes de Gemini
y evaluación con citas
literales y diagnóstico con acciones. Las preguntas sin marca se envían sin brief,
competidores ni respuesta esperada. Las preguntas con marca se separan del indicador
principal. Las preguntas propuestas no representan demanda de búsqueda observada.

El método v2 distingue búsquedas de categoría, búsquedas ajustadas al cliente y
ámbito de servicio, y reconocimiento al preguntar por la marca. Interpreta si el
negocio es local, regional o en línea; no inventa ubicaciones ni presupuestos.
Las preguntas sin marca deben buscar proveedores concretos, pasar una auditoría
independiente de intención, encaje y neutralidad y conservar su justificación.
Una revisión fallida permite una corrección automática antes de medir respuestas.
Los porcentajes de cada tipo tienen denominadores separados; las respuestas que
solo dan consejos siguen contando, y se muestra cuántas no nombran proveedores.

La extracción usa el modelo para resolver identidades y clasificar mención,
comparación, recomendación o desaconsejar. Conserva citas literales y el motivo de
identificación; admite alias, variantes y atributos en frases siguientes dentro
del mismo contexto. Una coincidencia de nombre o una fuente citada por sí sola
no establece identidad. La comprobación por patrones se limita a detectar marcas
filtradas en las preguntas, no decide la visibilidad. Las evidencias rechazadas
o contradictorias quedan como identidad ambigua, nunca como ausencia. Las
opciones nuevas que aparezcan en respuestas se muestran aparte; las referencias
sectoriales quedan fuera del ranking de competidores. La identidad pública
investigada se distingue del reconocimiento en respuestas.

Los nuevos trabajos utilizan `gemini-3.5-flash-lite` con pensamiento mínimo en
repositorios, documentos y visibilidad. Las tarifas estándar de texto verificadas
el 22/10/2026 son USD 0,30 de entrada y USD 2,50 de salida por millón de tokens,
más búsqueda cuando corresponda. Los estudios conservan el modelo y las tarifas
con los que se iniciaron; un método o modelo distinto requiere un panel nuevo.

El informe web se conserva en PostgreSQL: presencia, recomendaciones, citación de
la web propia, consistencia entre repeticiones, comparativa competitiva, matriz de
mercado e intención, preguntas/respuestas, fuentes, atributos, posibles discrepancias,
acciones y evolución comparable. Cada respuesta guarda la pregunta y la instrucción
exactas, modelo devuelto, configuración, fecha, citas y consumo. Briefs, investigación,
prompts y respuestas se cifran mediante Active Record Encryption. No se persiste el
pensamiento interno del proveedor. Los filtros y la consulta de informes no llaman a IA.

Las tasas se calculan en Ruby sobre toda la muestra válida. El diagnóstico cualitativo
usa hasta 80 respuestas repartidas entre mercados y etapas y conserva sus referencias. Las respuestas pendientes/fallidas y las identidades
ambiguas no se convierten en ausencias. La cuota de menciones solo compara las marcas
del panel y no es cuota de mercado. Los dominios sin resolver se excluyen del indicador
de citación propia. El mercado es contexto lingüístico/geográfico de la pregunta,
no una ubicación real. Las afirmaciones señaladas son candidatas a revisión, no errores
probados. El entorno medido es **Gemini API con búsqueda habilitada**: no representa
ChatGPT, Claude ni las interfaces de consumo. Google decide si ejecuta búsquedas en
cada respuesta; se conserva el número devuelto y se distinguen fuentes recuperadas de
citas enlazadas a un fragmento. La investigación requiere fuentes devueltas por Google.

Puedes pausar, continuar, cancelar, reiniciar o recuperar un fallo. La pausa se atiende
al acabar la petición en curso. Los reintentos automáticos de errores transitorios
están limitados a tres por tarea; una recuperación manual permite intentarlo de nuevo.
Las tareas completadas se reutilizan dentro del estudio. Reiniciar o volver a medir
recoge nuevas respuestas y tiene coste. Una respuesta HTTP perdida conserva su reserva
porque podría haber sido facturada. Los jobs duplicados están protegidos con un lock
consultivo de PostgreSQL. Tras 30 minutos sin actividad se ofrece recuperación.

Cada estudio tiene un presupuesto de hasta US$ 50 (por defecto US$ 3). Antes de cada
solicitud se reservan tokens de entrada de forma conservadora, toda la salida permitida
y hasta ocho consultas de búsqueda para los modelos facturados por consulta. Se
reconcilia con el uso devuelto y se pausa antes de la siguiente solicitud si no alcanza
el presupuesto. `VISIBILITY_DAILY_BUDGET_USD` limita el gasto estimado diario por usuario
(por defecto US$ 10, día de Europe/Madrid). `VISIBILITY_MAX_REQUESTS` y
`VISIBILITY_MAX_TOKENS` imponen topes de 1500 solicitudes y 2 millones de tokens por
estudio. No se permiten valores cero para estos topes.

**El coste es una estimación, no un máximo de factura:** Google no ofrece un límite
duro de consultas internas de Search por solicitud; una petición puede superar la
reserva. Las reservas de llamadas fallidas se mantienen, y la tarifa gratuita no se
descuenta. Las tarifas configuradas se guardan en cada estudio con fecha y fuente.
Revisa `Visibility::Settings::PRICING` al cambiar de modelo/precio y configura un
límite de cuota/facturación en Google si necesitas un control externo adicional.
Solo los modelos con tarifas explícitas se admiten en `VISIBILITY_GEMINI_MODEL`.

Para comparar evolución, reutiliza un panel completado con el mismo brief. Se recogen
respuestas nuevas y solo se dibuja una serie cuando hay al menos dos muestras completas
con la misma huella de panel, competidores, método, temperatura, repeticiones y versiones
de modelo devueltas. Cambiar el brief requiere un panel nuevo. Las acciones técnicas
pueden enviarse explícitamente a un repositorio del mismo usuario: los agentes de código
validan la recomendación contra sus archivos y usan el flujo existente de issues y PRs.
Los estudios de marca no publican por sí solos en GitHub.
