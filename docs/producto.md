# De la pregunta a la mejora

[← Documentación](README.md)

Fortop ofrece dos recorridos independientes, accesibles con GitHub. El usuario conecta un repositorio o crea una marca y puede seguir el trabajo hasta obtener un resultado persistente.

## 01 · Entender la visibilidad de una marca

**Brief → investigación → preguntas → respuestas → evidencia → plan de acción.**

1. **Crea la marca.** Nombre, negocio, público, mercados e idiomas. La web es opcional. Puedes aportar aliases y competidores conocidos.
2. **Añade contexto.** Arrastra documentos para que Fortop proponga el contenido del formulario. Revisa el resultado antes de estudiar la marca.
3. **Inicia el estudio.** Fortop interpreta el negocio, investiga competidores y prepara preguntas que buscaría un potencial cliente.
4. **Consulta el informe.** Presencia, recomendaciones, citación propia, competencia, mercados, respuestas, fuentes y acciones. Todo queda guardado.
5. **Actúa y compara.** Sigue las recomendaciones o envía una acción técnica a un repositorio. Reutiliza un panel comparable para medir de nuevo.

![Informe persistente de visibilidad](assets/brand-report.png)

*Interfaz real con datos de prueba de la marca Nébula.*

### Qué puedes consultar

| Vista | Te permite entender |
| :--- | :--- |
| Resumen | Cuándo te mencionan, recomiendan o citan |
| Competencia | Qué marcas aparecen en la misma muestra |
| Mercados e intención | Dónde y ante qué necesidades cambia tu presencia |
| Preguntas y respuestas | La consulta exacta, la respuesta y sus evidencias |
| Fuentes y percepción | Qué referencias se usan y qué atributos se te asignan |
| Acciones y evolución | Qué mejorar y qué cambia entre estudios comparables |

Las preguntas sin marca se ejecutan sin el brief ni la lista de competidores. Las preguntas que nombran la marca se miden aparte. [Cómo se calcula cada resultado →](metodologia.md)

## 02 · Mejorar la base técnica de una web

**Repositorio → análisis → correcciones → validación → issues y PR.**

1. **Conecta GitHub.** Instala la GitHub App y selecciona un repositorio al que tengas acceso.
2. **Inicia análisis y remediación.** Los agentes exploran archivos y contrastan los problemas encontrados.
3. **Sigue el trabajo.** La actividad muestra acciones y progreso; puedes pausar, continuar o cancelar.
4. **Revisa los hallazgos.** Cada uno explica qué ocurre, por qué afecta, la evidencia original y el motivo de la corrección.
5. **Revisa el PR.** Las correcciones verificadas se proponen en una rama de Fortop. Tu equipo conserva la revisión, el CI y la decisión de fusionar.

![Hallazgo con evidencia y diff](assets/code-finding.png)

*Ejemplo de prueba: una meta description vacía y la corrección propuesta.*

Se conservan comprobaciones, archivos revisados, actividad e historial. Los problemas sin corrección automática quedan documentados para intervención manual. [Cómo trabajan los agentes →](agentes.md)

## Un puente entre ambos recorridos

Desde una acción técnica del informe puedes elegir un repositorio propio. Fortop aporta el contexto al escaneo y comprueba la recomendación contra el código antes de proponer cambios. Una investigación de marca, por sí sola, no abre issues ni PRs.

## Control durante la ejecución

| Acción | Efecto |
| :--- | :--- |
| Pausar / continuar | Conserva el avance; la pausa se atiende en un punto seguro |
| Cancelar | Detiene el recorrido y conserva el historial |
| Recuperar un fallo | Reutiliza el trabajo recuperable de esa ejecución |
| Reiniciar / nuevo análisis | Crea una ejecución nueva; puede consumir IA de nuevo |

La consola muestra acciones y resultados de herramientas. Los informes guardan evidencia auditable; no exponen pensamiento interno del modelo.

## Acceso

Puedes **eliminar una marca** desde su página, junto a Editar brief. Tras confirmar, se borran la marca y sus estudios e informes. Los estudios activos o pausados deben cancelarse primero; los documentos compartidos con otras marcas se conservan.

La instancia del hackathon está desplegada en [Fortop](https://fortop.34-76-10-0.sslip.io). El administrador autoriza cuentas de GitHub desde el panel privado. Cada usuario consulta sus propios repositorios, marcas y documentos.
