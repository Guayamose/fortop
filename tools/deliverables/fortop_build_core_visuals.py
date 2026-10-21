from fortop_visual import *

def canvas():
    d=Diagram('Business Model Canvas','Fortop · del hallazgo técnico al cambio revisable','Modelo propuesto · 9 bloques',w=2520,h=1680,page='01')
    margin,gap=80,22
    cw=(2520-2*margin-4*gap)/5
    xs=[margin+i*(cw+gap) for i in range(5)]
    top,tall,half=225,900,439
    def block(col,y,h,num,title,items,tone='plain',bottom=None,icon=None):
        x=xs[col]
        color=d.panel(x,y,cw,h,tone)
        d.text(x+24,y+33,num,size=18,mono=True,color=color)
        title_y=d.paragraph(x+24,y+79,title,cw-48,size=29,line=38,color=color)
        cursor=title_y+30
        for item in items: cursor=d.bullet(x+26,cursor,item,cw-52,size=25,tone='pine' if tone=='plain' else tone)
        if cursor>y+h-30: raise ValueError(('canvas overflow',title,cursor,y+h))
        if bottom:
            d.path(f'M{x+25},{y+h-182} H{x+cw-25}',LINE,1)
            if icon: d.icon(icon,x+54,y+h-120,scale=1.2,color=color)
            d.paragraph(x+26,y+h-73,bottom,cw-52,size=21,line=30,color=MUTED)

    block(0,top,tall,'08 / RED','Socios clave',[
        'GitHub: acceso al código y publicación.',
        'Google Gemini: modelos para los agentes.',
        'Hosting y pagos: proveedores por seleccionar.'
    ],bottom='Proveedores e integraciones. Sin alianzas comerciales firmadas.',icon='flow')
    block(1,top,half,'07 / OPERACIÓN','Actividades clave',[
        'Investigar código y contrastar hallazgos.',
        'Preparar y validar correcciones.',
        'Medir calidad, uso y coste.'
    ])
    block(1,top+half+gap,half,'06 / CAPACIDAD','Recursos clave',[
        'Motor agéntico y validadores.',
        'GitHub, datos e historial.',
        'Equipo de producto, Rails y SEO.'
    ])
    x=xs[2]; color=d.panel(x,top,cw,tall,'pine')
    d.text(x+24,top+33,'02 / VALOR',size=18,mono=True,color=color)
    d.text(x+24,top+79,'Propuesta de valor',size=29,color=color)
    d.icon('check',x+70,top+190,scale=1.8,color=PINE)
    d.paragraph(x+26,top+295,'Del hallazgo\nal cambio\nrevisable.',cw-52,size=41,line=57,color=PINE)
    cy=top+515
    for item in ['Evidencia, corrección y PR en un flujo.','Menos trabajo manual de auditoría.','Control del equipo sobre cada cambio.']:
        cy=d.bullet(x+26,cy,item,cw-52,size=25,tone='pine')
    d.path(f'M{x+25},{top+tall-132} H{x+cw-25}',PINE,1)
    d.paragraph(x+26,top+tall-85,'Después: diagnóstico de visibilidad de marca en IA.',cw-52,size=21,line=30,color=PINE)
    block(3,top,half,'04 / VÍNCULO','Relación con clientes',[
        'Autoservicio guiado.',
        'Resultados trazables por ejecución.',
        'Pilotos con soporte directo.'
    ])
    block(3,top+half+gap,half,'03 / DISTRIBUCIÓN','Canales',[
        'Venta directa a agencias.',
        'Comunidad técnica y contenido.',
        'Referidos y demostraciones.'
    ])
    block(4,top,tall,'01 / CLIENTE','Segmentos de clientes',[
        'Agencias SEO y desarrollo web.',
        'Equipos web de pymes y marcas.',
        'Equipos técnicos que trabajan con GitHub.'
    ],tone='blue',bottom='Entrada inicial: agencias con varios proyectos web.',icon='person')
    bottom_y=1153; bottom_w=(2520-160-22)/2
    for x,title,num,items,tone in [
        (80,'Estructura de costes','09 / GASTOS',['Equipo, soporte y adquisición.','IA por ejecución e infraestructura.','Seguridad y mantenimiento.'],'plain'),
        (80+bottom_w+22,'Fuentes de ingresos','05 / INGRESOS',['Suscripción mensual B2B.','Cuotas de repositorios y ejecuciones.','Ampliaciones de uso y estudios de marca previstos.'],'green')]:
        color=d.panel(x,bottom_y,bottom_w,350,tone)
        d.text(x+26,bottom_y+34,num,size=18,color=color,mono=True)
        d.text(x+26,bottom_y+82,title,size=32,color=color)
        yy=bottom_y+145
        for item in items: yy=d.bullet(x+28,yy,item,bottom_w-56,size=26,tone='green' if tone=='green' else 'pine')
    d.footer('Modelo propuesto · repositorios operativo · visibilidad de marca prevista · 21 oct 2026')
    return d.save(OUT/'01-business-model-canvas/fortop-business-model-canvas')

def architecture():
    d=Diagram('cómo funciona Fortop','del repositorio a correcciones revisables','Implementado · ejecución local',page='03')
    d.boundary(450,260,1430,1070,'FORTOP · MONOLITO RAILS',subtitle='WEB + WORKER · MISMO CÓDIGO',color=INK)
    # Connections are drawn before the nodes, on reserved gutters.
    d.arrow([(380,545),(510,545)],label='HTTP',label_at=(444,520))
    d.arrow([(775,350),(775,220),(2145,220),(2145,335)],label='OAuth · repositorios autorizados',label_at=(1440,211))
    d.arrow([(775,700),(775,1080)],label='datos · encola jobs',label_at=(775,875))
    d.arrow([(1110,850),(1070,850),(1070,1160),(1040,1160)],tone='green',label='SQL',label_at=(1070,1010),bidir=True)
    d.arrow([(1800,505),(1890,505),(1890,455),(1970,455)],tone='green',label='código · PR',label_at=(1885,485),bidir=True)
    d.arrow([(1800,650),(1910,650),(1910,865),(1970,865)],tone='orange',label='modelo',label_at=(1907,735),bidir=True)
    d.arrow([(1270,970),(1270,1100)],tone='muted',label='lee y edita',label_at=(1270,1045))
    d.arrow([(1640,970),(1640,1100)],tone='purple',label='solo sintaxis',label_at=(1640,1045))

    d.icon('window',230,475,scale=3.1,color=BLUE)
    d.text(80,620,'Equipo web',size=35)
    d.text(82,662,'Navegador',size=21,mono=True,color=MUTED)
    d.paragraph(82,722,'Conecta y ejecuta.\nRevisa las propuestas.',290,size=26,line=41,color=MUTED)
    d.pill(82,870,'control del equipo',tone='blue',size=17)

    d.card(510,350,530,350,'Aplicación web','Rails 8.1 · Hotwire · Tailwind',[
        'Acceso y repositorios.',
        'Inicio de escaneos.',
        'Progreso, resumen e historial.'
    ],tone='blue',icon='window',body_size=25)

    d.panel(1110,350,690,620,'plain')
    d.icon('server',1145,394,scale=1.1,color=PINE)
    d.text(1180,399,'Worker de análisis',size=33)
    d.text(1136,436,'Solid Queue · proceso en segundo plano',size=19,mono=True,color=MUTED)
    stages=[('Agente de análisis','Lee · busca · documenta evidencia','orange','search'),('Agente de remediación','Edita · valida · repara o descarta','orange','agent'),('Validación independiente','Sintaxis · alcance · hallazgos','purple','check'),('Publicación en GitHub','Issues + PR en una rama fortop/*','green','git')]
    for index,(title,body,tone,icon) in enumerate(stages):
        yy=475+index*110
        color=d.panel(1140,yy,626,90,tone,depth=4)
        d.icon(icon,1167,yy+32,scale=.72,color=color)
        d.text(1196,yy+37,title,size=26,color=color)
        d.text(1164,yy+70,body,size=21,color=MUTED)
        d.text(1743,yy+34,f'0{index+1}',size=17,color=color,mono=True,anchor='end')
        if index<3: d.arrow([(1730,yy+94),(1730,yy+106)],tone='muted')

    d.panel(510,1080,530,180,'plain')
    d.icon('db',545,1123,scale=1.1,color=PINE)
    d.text(580,1129,'PostgreSQL',size=31)
    d.text(536,1166,'Dos bases lógicas · un servidor',size=18,mono=True,color=MUTED)
    d.text(536,1204,'Usuarios · escaneos · resultados',size=24)
    d.text(536,1236,'Datos del producto + cola de jobs',size=23,color=MUTED)

    for xx,title,subtitle,body,tone in [(1110,'Espacio temporal','Archivos + cambios','Se elimina al finalizar.','plain'),(1475,'Verificador JS','Docker · Node --check','Sin red; no ejecuta la app.','purple')]:
        color=d.panel(xx,1100,325,160,tone)
        d.text(xx+24,1150,title,size=25,color=color)
        d.text(xx+24,1188,subtitle,size=18,mono=True,color=MUTED)
        d.text(xx+24,1230,body,size=20,color=MUTED)
    d.card(1970,335,350,240,'GitHub','GitHub App',[
        'Identidad y permisos.',
        'Código · issues · PR.'
    ],icon='repo',title_size=31,body_size=24)
    d.card(1970,765,350,220,'Google Gemini','API de AI Studio',[
        'Decisiones y llamadas a herramientas.'
    ],tone='orange',title_size=29,body_size=24)
    d.text(510,1310,'Ramas fortop/* · revisión humana · sin merge automático',size=19,color=GREEN,mono=True)
    d.footer('Progreso mediante consultas JSON · validación estática · 21 oct 2026')
    return d.save(OUT/'03-arquitectura/fortop-arquitectura-actual')

if __name__=='__main__':
    print(canvas())
    print(architecture())
