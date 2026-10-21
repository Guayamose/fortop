from pathlib import Path
from fortop_visual import Diagram, OUT, BG, INK, MUTED, LINE, BLUE, ORANGE, GREEN, PINE, TONES, merge_pdfs

DEST = OUT / '04-c4'
SOURCE = ('Notación: c4model.com · código Fortop · 21 oct 2026', 'https://c4model.com/diagrams')

def type_label(d, x, y, text, tone='plain'):
    d.pill(x, y, text, tone=tone, size=17)

def legend(d, y, scope):
    d.text(82, y, 'CLAVES', size=17, mono=True, color=MUTED)
    for x, title, tone in [(245, 'Persona', 'plain'), (490, 'Fortop', 'blue'), (735, 'Servicio externo', 'orange')]:
        fill, color, shade = TONES[tone]
        d.rect(x, y-19, 22, 22, fill=fill, stroke=color, width=1.2)
        d.text(x+35, y, title, size=19, color=MUTED)
    d.text(d.w-82, y, scope, size=17, mono=True, color=MUTED, anchor='end')

def context():
    d=Diagram('Fortop en su entorno', 'C1 · contexto del sistema · análisis y remediación de repositorios', 'arquitectura implementada · local', page='C4 / 01')
    d.boundary(770,345,800,580,'SISTEMA EN ESTUDIO',color=BLUE,dashed=True)

    # The arrows are drawn first so cards remain visually opaque.
    d.arrow([(520,650),(850,650)], tone='blue', label='conecta · inicia · consulta', label_at=(685,620),size=18)
    d.arrow([(520,530),(645,530),(645,245),(2075,245),(2075,305)],tone='green',label='revisa y fusiona el PR',label_at=(1230,225),size=19)
    d.arrow([(1480,515),(1685,515),(1685,445),(1850,445)],tone='blue',label='identidad · código · PR',label_at=(1685,420),size=18)
    d.arrow([(1480,735),(1685,735),(1685,1000),(1850,1000)],tone='orange',label='decisiones y herramientas',label_at=(1685,968),size=19)

    d.card(80,460,440,350,'Equipo de producto','PERSONA',('Conecta un repositorio.','Inicia el análisis y revisa las correcciones.'),tone='plain',icon='person',title_size=29,body_size=27)
    d.card(850,440,630,390,'Fortop','SISTEMA DE SOFTWARE',('Investiga el código con agentes.','Propone mejoras SEO/GEO.','Muestra progreso y resultados.'),tone='blue',icon='chart',title_size=39,body_size=28)
    d.card(1850,305,450,300,'GitHub','SISTEMA EXTERNO',('Identidad y repositorios.','Issues, ramas y PRs.'),tone='plain',icon='git',title_size=34,body_size=27)
    d.card(1850,865,450,285,'Google Gemini','SISTEMA EXTERNO',('Modelo de los agentes.','API de Google AI Studio.'),tone='orange',icon='agent',title_size=33,body_size=26)

    d.path('M850,1030 H1475',LINE,1.2)
    d.text(850,1073,'EL RESULTADO ES UNA PROPUESTA',size=18,mono=True,color=BLUE)
    d.paragraph(850,1114,'El equipo revisa el PR y decide cuándo fusionarlo.',650,size=26,line=37,color=INK)
    legend(d,1290,'Alcance: código · la visibilidad de marca es futura')
    d.footer('C1 · relaciones del producto con personas y sistemas externos',source=SOURCE)
    return d.save(DEST/'fortop-c4-01-contexto')

def containers():
    d=Diagram('Las piezas de Fortop','C2 · contenedores · un monolito, dos procesos y PostgreSQL','arquitectura implementada · local',page='C4 / 02')
    d.boundary(485,255,1260,975,'SISTEMA FORTOP',color=BLUE)

    d.arrow([(410,535),(560,535)],tone='blue',label='HTTP',label_at=(483,510),size=19)
    d.arrow([(805,700),(805,900)],tone='blue',label='datos + encola · SQL',label_at=(805,810),size=19)
    d.arrow([(1415,700),(1415,900)],tone='purple',label='jobs + resultados · SQL',label_at=(1415,810),size=19)
    d.arrow([(1050,460),(1100,460),(1100,310),(2095,310),(2095,360)],tone='blue',label='OAuth + repos autorizados · HTTPS',label_at=(1480,290),size=18)
    d.arrow([(1680,490),(1870,490)],tone='blue',label='HTTPS',label_at=(1775,465),size=19)
    d.arrow([(1680,610),(1795,610),(1795,995),(1870,995)],tone='orange',label='function calling',label_at=(1795,835),size=18)

    d.card(80,420,330,280,'Usuario','PERSONA',('Navegador web.','Conecta, ejecuta y consulta.'),tone='plain',icon='person',title_size=31,body_size=26)
    d.card(560,380,490,320,'Aplicación web','CONTENEDOR · RAILS / PUMA',('Acceso y repositorios.','Inicio y consulta de escaneos.','Hotwire · Tailwind · SSR'),tone='blue',icon='window',title_size=32,body_size=25)
    d.card(1150,380,530,320,'Worker de análisis','CONTENEDOR · RAILS / SOLID QUEUE',('Ejecuta agentes y herramientas.','Valida y publica propuestas.','Google Gemini · dos agentes'),tone='purple',icon='agent',title_size=31,body_size=25)
    d.card(560,900,1120,245,'PostgreSQL','ALMACÉN DE DATOS · SQL',('Usuarios, repositorios, escaneos, hallazgos y eventos.','Datos de plataforma + cola: dos bases lógicas en el mismo servidor.'),tone='plain',icon='db',title_size=34,body_size=26)
    d.card(1870,360,450,275,'GitHub','SISTEMA EXTERNO · GITHUB APP',('Identidad y autorización.','Código, issues y PRs.'),tone='plain',icon='git',title_size=34,body_size=26)
    d.card(1870,885,450,255,'Google Gemini','SISTEMA EXTERNO · AI STUDIO',('Modelo y herramientas.','API HTTPS de Gemini.'),tone='orange',icon='cloud',title_size=32,body_size=26)

    d.text(560,1195,'Progreso: consultas JSON periódicas desde Stimulus.',size=21,color=MUTED,mono=True)
    d.text(82,1300,'VERIFICACIÓN JAVASCRIPT',size=17,color=MUTED,mono=True)
    d.text(480,1300,'Docker efímero · Node --check · sin red · no ejecuta la aplicación',size=23,color=INK)
    legend(d,1360,'Contenedor C4 = aplicación o almacén de datos')
    d.footer('C2 · procesos y almacén de datos del vertical actual',source=SOURCE)
    return d.save(DEST/'fortop-c4-02-contenedores')

def components():
    d=Diagram('Por dentro de los agentes','C3 · componentes del worker · decisiones de IA, ejecución controlada por Rails','arquitectura implementada · local',w=2600,h=1600,page='C4 / 03')
    d.boundary(80,275,1830,1140,'WORKER · PROCESO RAILS / SOLID QUEUE',subtitle='un único contenedor en detalle',color=BLUE)

    # Three direct orchestration paths, then the agent's local/remote tools.
    d.arrow([(365,550),(365,770)],tone='purple',label='verificación final',label_at=(365,672),size=20)
    d.arrow([(995,550),(995,770)],tone='orange',label='dos fases secuenciales',label_at=(995,672),size=20)
    d.arrow([(1605,550),(1605,770)],tone='blue',label='autoriza y publica',label_at=(1605,672),size=20)
    d.arrow([(1815,445),(2050,445)],tone='purple',label='SQL',label_at=(1933,420),size=20)
    d.arrow([(995,1070),(995,1170)],tone='orange',label='lee · edita',label_at=(995,1132),size=18)
    d.arrow([(595,965),(665,965),(665,1270),(735,1270)],tone='purple',label='lee cambios',label_at=(665,1130),size=18)
    d.arrow([(1815,920),(2050,920)],tone='blue',label='HTTPS',label_at=(1933,895),size=20)
    d.arrow([(1255,885),(1320,885),(1320,1270),(2050,1270)],tone='orange',label='function calling · HTTPS',label_at=(1685,1245),size=20)

    d.card(135,350,1680,200,'Orquestador','ScanJob · Scans::Pipeline · Ruby',('Coordina fases, persiste progreso, verifica propuestas y recupera publicaciones.',),tone='blue',icon='flow',title_size=35,body_size=28)
    d.card(135,770,460,300,'Validador independiente','Scans::Validator · Ruby',('Sintaxis, alcance y hallazgos.','JavaScript: Node en Docker.','Sin red; no ejecuta la app.'),tone='purple',icon='check',title_size=27,body_size=24)
    d.card(735,770,520,300,'Motor de agentes','Runner · GeminiClient · Toolsets',('1 · Análisis con evidencias.','2 · Remediación de hallazgos.','Decide → actúa → observa.'),tone='orange',icon='agent',title_size=32,body_size=25)
    d.card(1395,770,420,300,'Integración GitHub','Access · App · Client',('Autoriza por repositorio.','Lee código y publica.','Ramas, issues y PRs.'),tone='blue',icon='git',title_size=28,body_size=25)
    d.card(735,1170,520,220,'Workspace temporal','Scans::Workspace · archivos locales',('Instantánea del commit y cambios propuestos.',),tone='plain',icon='repo',title_size=30,body_size=25)
    d.card(2050,350,470,240,'PostgreSQL','CONTENEDOR · DATOS + COLA',('Escaneos, hallazgos y eventos.','Jobs de Solid Queue.'),tone='plain',icon='db',title_size=31,body_size=25)
    d.card(2050,800,470,250,'GitHub','SISTEMA EXTERNO',('Permisos y código.','Issues, ramas y PRs.'),tone='plain',icon='git',title_size=34,body_size=26)
    d.card(2050,1150,470,250,'Google Gemini','SISTEMA EXTERNO · AI STUDIO',('Responde y pide herramientas.','Presupuesto de tokens acotado.'),tone='orange',icon='cloud',title_size=32,body_size=25)

    d.text(82,1472,'COMPONENTES',size=17,mono=True,color=MUTED)
    for x,title,tone in [(300,'Orquestación','blue'),(650,'Agentes','orange'),(940,'Verificación','purple')]:
        fill,color,_=TONES[tone]
        d.rect(x,1453,22,22,fill=fill,stroke=color,width=1.2)
        d.text(x+35,1472,title,size=19,color=MUTED)
    d.text(2518,1472,'Agentes = roles del mismo motor; no son microservicios.',size=17,mono=True,color=MUTED,anchor='end')
    d.footer('C3 · el worker usa componentes Ruby y servicios externos',source=SOURCE)
    return d.save(DEST/'fortop-c4-03-componentes',scale=3600/2600)

if __name__ == '__main__':
    paths=[context(),containers(),components()]
    merge_pdfs([p.with_suffix('.pdf') for p in paths],DEST/'fortop-c4.pdf')
    for p in paths: print(p)
