from pathlib import Path
from fortop_visual import Diagram, OUT, INK, MUTED, BLUE, GREEN, ORANGE, PURPLE, PINE, LINE, TONES, merge_pdfs


DEST = OUT / '02-business-plan'
X = (80, 840, 1600)
Y = (250, 790)
W, H = 720, 490


def panel(d, col, row, title, subtitle='', tone='plain', icon='brief'):
    x, y = X[col], Y[row]
    color = d.panel(x, y, W, H, tone=tone)
    d.icon(icon, x+37, y+43, scale=.95, color=color)
    d.text(x+76, y+53, title, size=31, color=color)
    if subtitle:
        d.text(x+30, y+94, subtitle.upper(), size=17, color=MUTED, mono=True)
    return x, y, color


def bullets(d, x, y, items, tone='blue', start=148, size=26, gap=22):
    cy = y+start
    for item in items:
        cy = d.bullet(x+33, cy, item, W-66, size=size, tone=tone)+gap
    if cy-gap-18 > y+H-25:
        raise ValueError(('business_bullet_overflow', items, cy, y+H))


def pair(d, x, y, title, body, color=INK, size=24):
    d.text(x, y, title, size=25, color=color)
    return d.paragraph(x, y+36, body, W-64, size=size, line=34, color=MUTED)


def rule(d, x, y):
    d.path(f'M{x},{y} H{x+W-64}', LINE, 1)


def model():
    d = Diagram('Del diagnóstico al cambio',
                'Fortop · propuesta de valor, cliente y modelo comercial',
                'Business plan · propuesta', page='02 / 01')
    d.pill(82, 190, 'Repositorios: operativo', tone='pine', size=18)
    d.pill(460, 190, 'Marca: siguiente vertical', tone='purple', size=18)
    d.text(2318, 215, 'TÉCNICA PROBADA · NEGOCIO POR VALIDAR', size=18, color=MUTED, mono=True, anchor='end')

    x,y,c = panel(d,0,0,'El problema','Del informe a la implementación','plain','search')
    bullets(d,x,y,[
        'Las auditorías dejan tareas que alguien debe ejecutar.',
        'Marketing y desarrollo manejan prioridades distintas.',
        'Repetir revisiones consume tiempo del equipo.',
    ],tone='plain',start=155,gap=14)

    x,y,c = panel(d,1,0,'La propuesta de valor','Mejora técnica SEO / GEO','blue','check')
    bullets(d,x,y,[
        'Encontrar problemas con evidencia del código.',
        'Preparar correcciones y comprobar su alcance.',
        'Entregar issues y PRs para revisión humana.',
    ],tone='blue',start=155,gap=14)

    x,y,c = panel(d,2,0,'El cliente inicial','B2B · equipos que usan GitHub','plain','person')
    bullets(d,x,y,[
        'Agencias de SEO y desarrollo web.',
        'Equipos web de pymes y marcas.',
        'Compra: responsable de agencia o equipo web.',
    ],tone='plain',start=155,gap=24)

    x,y,c = panel(d,0,1,'El producto actual','Dos agentes coordinados por Rails','pine','agent')
    steps = [('01','Conectar GitHub'),('02','Analizar y remediar'),('03','Revisar issues y PRs')]
    for i,(n,title) in enumerate(steps):
        sy=y+132+i*97
        d.pill(x+32,sy,n,tone='pine',size=18)
        d.text(x+114,sy+27,title,size=28,color=PINE)
        if i<2:
            d.arrow([(x+62,sy+43),(x+62,sy+84)],tone='pine')
    d.text(x+32,y+449,'Progreso · resumen · historial',size=21,color=MUTED,mono=True)

    x,y,c = panel(d,1,1,'La entrada al mercado','Pilotos antes de escalar','orange','chart')
    bullets(d,x,y,[
        'Captar agencias para pilotos acompañados.',
        'Medir tiempo, coste y aceptación de cambios.',
        'Convertir pilotos en suscripciones con cuotas.',
    ],tone='orange',start=155,gap=14)

    x,y,c = panel(d,2,1,'La evolución prevista','Visibilidad de marca · por desarrollar','purple','brief')
    bullets(d,x,y,[
        'Interpretar el brief, mercados y competidores.',
        'Diagnosticar presencia por motor, geografía y fuente.',
        'Validar metodología y ampliar el producto.',
    ],tone='purple',start=155,gap=14)
    d.footer('Mejora técnica accionable · sin garantías de ranking ni de menciones en motores de IA')
    return d.save(DEST/'01-propuesta-de-valor-y-modelo')


def economics():
    d = Diagram('Costes visibles, crecimiento medible',
                'Fortop · recursos y viabilidad económica mensual',
                'Business plan · economía', page='02 / 02')
    d.pill(82,190,'Hipótesis · validar en piloto',tone='orange',size=18)
    d.text(2318,215,'SIN VENTAS NI RENTABILIDAD VALIDADAS',size=18,color=MUTED,mono=True,anchor='end')

    x,y,c = panel(d,0,0,'Precios propuestos','Cuotas mensuales · sin impuestos','blue','coins')
    positions = [x+31,x+294,x+452,x+582]
    for px,label in zip(positions,['PLAN','€/MES','REPOS.','EJEC.']):
        d.text(px,y+146,label,size=18,mono=True,color=MUTED)
    rule(d,x+32,y+164)
    plans=[('Inicio','49 €','1','5'),('Equipo','149 €','5','20'),('Agencia','399 €','20','60')]
    for i,plan in enumerate(plans):
        for px,value in zip(positions,plan):
            d.text(px,y+213+i*67,value,size=27,color=BLUE)
    d.paragraph(x+32,y+409,'Una ejecución incluye análisis y remediación con límites.',W-64,size=22,line=31,color=MUTED)

    x,y,c = panel(d,1,0,'Por cuenta','Supuesto de mezcla de planes','plain','person')
    metrics=[('99 €','Ingreso medio mensual',INK),('20 €','Coste variable mensual',ORANGE),('79 €','Contribución antes de costes fijos',PINE)]
    for i,(value,label,color) in enumerate(metrics):
        sy=y+158+i*122
        d.text(x+32,sy,value,size=48,color=color,mono=True)
        d.text(x+32,sy+39,label,size=24,color=MUTED)
        if i == 1:
            d.text(x+32,sy+70,'IA, ejecución y soporte variable',size=21,color=MUTED)

    x,y,c = panel(d,2,0,'Costes fijos previstos','Supuestos · no gastos actuales','plain','server')
    d.text(x+32,y+172,'6.400 € / mes',size=49,color=INK,mono=True)
    rule(d,x+32,y+213)
    d.text(x+32,y+277,'400 €',size=32,color=BLUE,mono=True)
    d.text(x+210,y+277,'Infraestructura',size=25,color=INK)
    d.text(x+32,y+351,'6.000 €',size=32,color=PINE,mono=True)
    d.text(x+210,y+351,'Equipo parcial',size=25,color=INK)
    d.paragraph(x+32,y+416,'Ajustar según soporte, captación y uso.',W-64,size=23,line=32,color=MUTED)

    x,y,c = panel(d,0,1,'Escenario · 100 cuentas','Ejemplo mensual · no previsión','green','chart')
    rows=[('Ingresos','9.900 €'),('Costes variables','−2.000 €'),('Costes fijos','−6.400 €')]
    for i,(label,value) in enumerate(rows):
        sy=y+147+i*63
        d.text(x+32,sy,label,size=26,color=INK)
        d.text(x+W-34,sy,value,size=29,color=INK,mono=True,anchor='end')
    rule(d,x+32,y+306)
    d.text(x+32,y+383,'1.500 €',size=58,color=PINE,mono=True)
    d.text(x+32,y+430,'Resultado mensual antes de impuestos',size=24,color=MUTED)

    x,y,c = panel(d,1,1,'Punto de equilibrio','79 € de contribución por cuenta','orange','flow')
    d.text(x+32,y+167,'82 cuentas',size=51,color=ORANGE,mono=True)
    d.text(x+32,y+213,'Cubren infraestructura + equipo',size=26,color=INK)
    rule(d,x+32,y+253)
    d.text(x+32,y+320,'6 cuentas',size=46,color=MUTED,mono=True)
    d.text(x+32,y+363,'Cubren solo infraestructura',size=25,color=INK)
    d.text(x+32,y+402,'Excluye el coste del equipo',size=22,color=MUTED)
    d.text(x+32,y+455,'Fijo ÷ 79 € · redondeado al alza',size=18,color=MUTED,mono=True)

    x,y,c = panel(d,2,1,'Recursos clave','Capacidad técnica y de negocio','purple','brief')
    pairs=[('Producto y negocio','Pilotos, soporte y ventas'),('Ingeniería Rails e IA','Aplicación y agentes'),('Criterio SEO / GEO','Hallazgos y evaluación'),('Servicios tecnológicos','GitHub, Gemini, PostgreSQL y hosting')]
    for i,(title,body) in enumerate(pairs):
        pair(d,x+32,y+137+i*89,title,body,color=PURPLE,size=23)
    d.footer('Hipótesis de planificación · medir costes, soporte, conversión y retención antes de escalar')
    return d.save(DEST/'02-costes-recursos-y-viabilidad')


def implementation():
    d=Diagram('Implantar, medir y ampliar',
              'Fortop · implantación, sostenibilidad y barreras',
              'Business plan · ejecución',page='02 / 03')
    d.pill(82,190,'Calendario orientativo',tone='blue',size=18)
    d.text(2318,215,'ETAPAS DESDE EL ARRANQUE DEL PILOTO',size=18,color=MUTED,mono=True,anchor='end')

    x,y,c=panel(d,0,0,'Implantación por etapas','Avanzar según resultados','blue','flow')
    stages=[('AHORA','Vertical de repositorios probado'),('SEMANAS 2–4','Pilotos HTTPS y ajuste de cuotas'),('SEMANAS 5–8','Despliegue público, cobro y operación'),('SEMANAS 9–12','Validar y prototipar marca')]
    for i,(label,body) in enumerate(stages):
        sy=y+134+i*86
        d.text(x+32,sy,label,size=18,color=BLUE,mono=True)
        d.paragraph(x+32,sy+35,body,W-64,size=25,line=34,color=INK)

    x,y,c=panel(d,1,0,'Calidad y control','Base actual + tareas de producción','plain','check')
    bullets(d,x,y,[
        'Permisos por repositorio y credenciales protegidas.',
        'Evidencia y validación del cambio.',
        'PR revisable; decisión final del equipo.',
        'Producción: copias y alertas.',
    ],tone='plain',start=147,size=25,gap=4)

    x,y,c=panel(d,2,0,'Sostenibilidad','Objetivos de operación','green','leaf')
    dimensions=[('Económica','Cuotas y margen por cuenta'),('Operativa','Colas, trazabilidad y límites'),('Ambiental','Acotar lecturas, tokens y reintentos'),('Humana','Cambios explicables y revisables')]
    for i,(title,body) in enumerate(dimensions):
        pair(d,x+32,y+136+i*88,title,body,color=GREEN,size=23)

    x,y,c=panel(d,0,1,'Barreras técnicas','Riesgo → respuesta','orange','lock')
    risks=[('Acceso a código privado','Permisos mínimos y transparencia.'),('Errores de IA','Evidencia, validación y revisión por PR.'),('Dependencia de proveedores','Integraciones acotadas y límites de uso.')]
    for i,(title,body) in enumerate(risks):
        pair(d,x+32,y+143+i*111,title,body,color=ORANGE,size=24)

    x,y,c=panel(d,1,1,'Barreras comerciales','Riesgo → respuesta','purple','person')
    risks=[('Retorno poco claro','Medir tiempo y cambios aceptados.'),('Competencia e inercia','Pilotos en el flujo GitHub existente.'),('Expectativas de ranking','Explicar alcance y evitar garantías.')]
    for i,(title,body) in enumerate(risks):
        pair(d,x+32,y+143+i*111,title,body,color=PURPLE,size=24)

    x,y,c=panel(d,2,1,'Validación del piloto','Utilidad + viabilidad','pine','chart')
    bullets(d,x,y,[
        'Tiempo desde inicio hasta PR.',
        'Correcciones aceptadas y rechazadas.',
        'Coste por ejecución y por cuenta.',
        'Conversión a pago y continuidad.',
    ],tone='pine',start=148,size=25,gap=5)
    d.footer('Calendario propuesto · sin compromisos de fecha ni estimaciones de CO₂ no medidas')
    return d.save(DEST/'03-implantacion-sostenibilidad-y-barreras')


if __name__ == '__main__':
    outputs=[model(),economics(),implementation()]
    merge_pdfs([path.with_suffix('.pdf') for path in outputs],DEST/'fortop-business-plan.pdf')
    print('\n'.join(str(path) for path in outputs))
