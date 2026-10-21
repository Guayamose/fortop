# Fortop — contexto y flujo acordado

Última actualización: 20 de octubre de 2026.

## Idea del producto

Una plataforma de GEO con dos áreas: estudiar la visibilidad de una marca en
motores de IA a partir de un brief y analizar y corregir repositorios mediante
issues y pull requests en GitHub.

La configuración debe ser mínima. Cada área tiene su propio punto de entrada:
un repositorio conectado o un brief de marca. Los agentes trabajan en el backend
y el usuario consulta el progreso y los resultados.

## Navegación propuesta

Dos pestañas principales, con estos nombres propuestos:

- **Análisis y remediación:** repositorios conectados, ejecuciones y correcciones.
- **Visibilidad de marca:** briefs, estudios de competidores y diagnóstico de
  presencia en motores de IA.

## Historia de usuario: análisis y remediación de repositorios

1. El usuario entra en la aplicación e inicia sesión con GitHub.
2. En el área de análisis y remediación accede a una pantalla vacía con un botón:
   **«Conectar un repositorio»**.
3. Pulsa el botón y elige uno de los repositorios de su cuenta de GitHub.
4. El repositorio conectado aparece en la plataforma.
5. Pulsa sobre el repositorio y entra en su perfil dentro de la aplicación.
6. En ese perfil encuentra el botón **«Iniciar análisis y remediación»**.
7. Al pulsarlo, comienza todo el proceso en el backend: análisis del código,
   detección de problemas y oportunidades de SEO/GEO, generación de correcciones
   y creación de issues y PRs en GitHub.
8. Durante la ejecución, ve una línea de progreso que refleja lo que está
   ocurriendo. No necesita aportar información adicional ni dirigir a los agentes.
9. Cuando la ejecución termina correctamente, aparece un tick de finalización.
10. En GitHub quedan los issues y PRs generados. En el perfil del repositorio
    aparece un resumen de ese escaneo con los hallazgos, las acciones realizadas
    y los enlaces a los issues y PRs.

Flujo principal: **conectar repositorio → ejecutar → ver progreso → consultar
resultado**.

## Historia de usuario: visibilidad de marca

Como usuario o dueño de una marca, quiero aportar un brief para entender cómo
aparece mi negocio frente a sus competidores en las búsquedas y respuestas de
plataformas de IA, por mercado, geografía y etapa del embudo.

1. El usuario inicia sesión con GitHub y abre **«Visibilidad de marca»**.
2. Introduce un brief de su marca. Puede explicar el negocio, sus productos o
   servicios, su público y los mercados o geografías que le interesan.
3. Inicia el estudio. El sistema interpreta el brief y prepara el contexto del
   negocio, el público, los mercados y los competidores que va a estudiar.
4. El backend investiga la competencia y evalúa la presencia relativa de la
   marca en búsquedas y respuestas de distintos motores de IA. ChatGPT y Claude
   son ejemplos de plataformas que se quieren evaluar; las integraciones
   concretas quedan pendientes de definir.
5. El usuario consulta el progreso mientras se ejecuta el estudio.
6. Al terminar, obtiene un diagnóstico de visibilidad y posicionamiento frente
   a competidores, con un resumen y oportunidades de mejora.

El estudio debe permitir entender:

- **Visibilidad:** cuándo aparece la marca, cómo se la presenta y si se la cita
  o recomienda en las respuestas observadas.
- **Competencia:** qué otras marcas aparecen y cómo se sitúa la marca frente a
  ellas para las mismas consultas.
- **Geografías y mercados:** cómo varían los resultados entre los ámbitos
  estudiados.
- **Embudo:** presencia en consultas de descubrimiento, consideración y decisión.
- **Motores:** diferencias entre las plataformas de IA evaluadas.
- **Fuentes:** qué páginas y dominios aparecen citados y respaldan las respuestas.

Las conclusiones deben apoyarse en las consultas realizadas, las respuestas
observadas, sus fuentes y la fecha de la medición. Lo que no se haya medido no
debe presentarse como un resultado del estudio.

Flujo principal: **aportar brief → iniciar estudio → ver progreso → consultar
diagnóstico**.

Este estudio puede iniciarse sin conectar un repositorio. La relación entre una
marca y sus repositorios, y cómo sus hallazgos pueden alimentar la remediación,
quedan pendientes de concretar.

## Organización interna acordada

- **Agente de análisis GEO:** inspecciona código y contenido, identifica la
  empresa y la web cuando es posible y detecta problemas y oportunidades. El
  descubrimiento del contexto forma parte de este agente.
- **Agente de remediación:** toma los hallazgos que puede resolver mediante
  código, genera cambios, ejecuta comprobaciones y abre los PRs para revisión.
- Ambos forman parte de la misma ejecución de análisis y remediación iniciada
  con un único botón en el perfil del repositorio.
- Los PRs quedan para revisión; no se fusionan automáticamente.
- El estudio de marca interpreta el brief y realiza la investigación competitiva
  y de visibilidad. Su implementación interna todavía no se ha definido.

Las correcciones técnicas se verifican durante el proceso. La evolución de la
visibilidad real en respuestas de IA requiere mediciones posteriores al
despliegue; no se deduce únicamente del código ni se garantiza por abrir un PR.
Los informes y la monitorización continua forman parte de la visión del producto.

## Base técnica y estado actual

Estado actualizado el **21 de octubre de 2026**: el vertical de análisis y
remediación está implementado sobre Rails 8.1, Ruby 3.3.5, PostgreSQL, Hotwire,
Tailwind CSS y Solid Queue.

Las carpetas del proyecto son:

- **`fortop_platform/`:** monolito Rails, interfaz, datos, trabajos y sistemas
  agénticos. Este documento pertenece a esta carpeta.
- **`fortop_github_app/`:** manifiesto, utilidades e instrucciones de registro de
  la GitHub App. La integración se ejecuta dentro del monolito Rails.
- **`fortop_brand_kit/`:** originales de la identidad visual. La aplicación usa
  sus SVG y los colores Pine Teal, Ivory, Honeydew y Shadow Grey, sin modificar
  los originales.

Está implementado el recorrido completo: acceso con GitHub, pantalla vacía,
selección de repositorios autorizados, conexión, perfil, inicio de una
ejecución, progreso automático, historial y resultados con enlaces a GitHub.
Cada usuario solo accede a sus repositorios y ejecuciones. La GitHub App permite
elegir repositorios y utiliza tokens de instalación limitados al repositorio
correspondiente; la sesión de `gh` de la máquina no identifica a los visitantes.

El backend coordina **dos agentes con bucles de herramientas**. El agente de
análisis decide qué archivos examinar y registra hallazgos con evidencias. El
de remediación consulta esos hallazgos y prepara cambios. La orquestación
verifica las propuestas y publica issues y un pull request cuando corresponde.
El progreso y las acciones quedan persistidos. Los errores conservan los
resultados parciales; las ejecuciones sin cambios lo indican expresamente.
Una corrección propuesta en un PR no se considera desplegada ni fusionada.

Los agentes usan **exclusivamente Google Gemini mediante AI Studio**, con
`GOOGLE_AI_STUDIO_API_KEY` y alternativa `GEMINI_API_KEY`. Las claves de OpenAI y
Anthropic quedan reservadas para otros usos y no alimentan estos agentes. El
modelo se elige con `GEMINI_MODEL`. Hay presupuestos configurables de turnos,
llamadas a herramientas, salida y tokens totales; el presupuesto total se
comparte entre ambos agentes. También se limita la lectura y el tamaño de los
cambios para acotar el alcance del escaneo.

El análisis es estático y acotado. Se excluyen archivos sensibles por nombre y
por patrones de contenido con prefijos reconocibles de credenciales. Este
detector es heurístico: **no equivale a un escáner completo de secretos**.
Las comprobaciones técnicas tampoco sustituyen las pruebas y la revisión del
repositorio de destino.

Se han ejecutado pruebas automatizadas de modelos, integración GitHub, agentes,
orquestación y controladores, además de una prueba de navegador con Chrome que
recorre el acceso, la conexión, el inicio y la actualización real del progreso
mediante Stimulus, en escritorio y móvil. También se han comprobado el arranque,
Zeitwerk, RuboCop y la compilación de los estilos.

La GitHub App real **[fortop-app](https://github.com/apps/fortop-app)** ya está
registrada bajo la cuenta **Guayamose** y configurada en la plataforma local.
Su ficha es pública e instalable. Los callbacks siguen apuntando a
`http://localhost:3000`: la existencia de la App pública no significa que la
plataforma esté desplegada en producción.

La prueba real completa ya ha terminado: **login → instalación → conexión desde
la interfaz → Solid Queue → dos agentes Google → ocho comprobaciones →
publicación por `app/fortop-app` → interfaz al 100 % con el PR visible**. La App
se instaló con acceso restringido únicamente al repositorio privado de prueba.
El [escaneo #3](http://localhost:3000/repositories/2/scans/3) registró dos
hallazgos, meta description y JSON-LD, y propuso ambas correcciones en un HTML
con 14 líneas añadidas: **11 peticiones a Google y 18.669 tokens**. Los resultados
son el [issue #3](https://github.com/Guayamose/fortop-integration-check-ee2bda/issues/3)
y el [PR #4](https://github.com/Guayamose/fortop-integration-check-ee2bda/pull/4),
abierto y **sin fusionar**; la rama principal conserva su SHA.

La prueba detectó una pérdida de atribución al editar dos veces el mismo archivo.
Se corrigió conservando la unión de hallazgos y se añadieron pruebas. Después
se revalidó el diff publicado con las ocho comprobaciones y se reconcilió el
escaneo sin nuevas llamadas a Google: **dos correcciones propuestas y cero
intervenciones manuales**.

Las credenciales están guardadas en `.env` con permisos `0600`; se han eliminado
las copias temporales utilizadas para conectarla.

Para arrancar desde `fortop_platform/`:

```sh
bin/dev
```

Las instrucciones de instalación están en [README.md](README.md).

## Punto de continuación

El vertical completo ya está comprobado con la App real. Los siguientes pasos
son **conectar un repositorio real del usuario**, desplegar Rails con sus
callbacks de producción e implementar el estudio de marca. No hay que repetir
el registro ni la comprobación inicial de instalación.

El próximo vertical de producto será **Visibilidad de marca**. Sigue pendiente
de implementar: brief, investigación competitiva, consultas a motores de IA,
diagnóstico por mercado, geografía, embudo y fuentes, y sus resultados. La
navegación solo lo anuncia como próximo. Su alcance y la relación entre marcas
y repositorios se concretarán sobre las historias de usuario anteriores, usando
la base común ya construida.
