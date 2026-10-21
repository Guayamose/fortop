from pathlib import Path
import json, math, html, shutil, re, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

BASE=Path(__file__).resolve().parent
ROOT=Path(os.environ.get('FORTOP_OUTPUT',str(BASE.parent.parent/'FORTOP_Brand_Kit_rebuild'))).resolve()
REF=Path(os.environ.get('FORTOP_REFERENCES',str(BASE.parent/'99_REFERENCIAS'))).resolve()
ROOT.mkdir(parents=True,exist_ok=True)
C={'shadow':'#2E282A','pine':'#2B4F42','ivory':'#FFFFF3','honeydew':'#E0EFDA'}
D,P,I,H=C.values()
FONT=TTFont('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
BOLD=TTFont('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
# Manual reconstruction from the selected ASCENSO reference. No tracing.
PLANES=[('ala-izquierda',[(0,142),(48,88),(48,172),(0,192)],P),
        ('plano-central-izquierdo',[(64,66),(110,0),(110,146),(64,165)],D),
        ('plano-central-derecho',[(122,16),(164,68),(164,165),(122,147)],P),
        ('ala-derecha',[(178,88),(224,142),(224,192),(178,172)],P)]
# SÓLIDO: six custom drawn glyphs. These paths are NOT a typeset font.
GLYPHS={
'F':'M0 0H98V22H24V42H82V64H24V100H0Z',
'O':'M25 0H87Q112 0 112 25V75Q112 100 87 100H25Q0 100 0 75V25Q0 0 25 0Z M31 23Q24 23 24 30V70Q24 77 31 77H81Q88 77 88 70V30Q88 23 81 23Z',
'R':'M0 0H88Q112 0 112 24V42Q112 62 92 65L116 100H86L61 66H24V100H0Z M24 22V44H82Q88 44 88 38V28Q88 22 82 22Z',
'T':'M0 0H110V23H67V100H43V23H0Z',
'P':'M0 0H86Q110 0 110 24V42Q110 66 86 66H24V100H0Z M24 22V44H80Q86 44 86 38V28Q86 22 80 22Z'}
POS=[0,115,246,375,500,631]
WW=741

def pathpoly(points): return 'M'+'L'.join(f'{x:g} {y:g}' for x,y in points)+'Z'
def esc(t):return html.escape(str(t))
def tr(content,x=0,y=0,s=1):return f'<g transform="translate({x:g} {y:g}) scale({s:g})">{content}</g>'
def rect(x,y,w,h,c,rx=0,stroke=None,sw=1):return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{c}"'+(f' stroke="{stroke}" stroke-width="{sw:g}"' if stroke else '')+'/>'
def line(x1,y1,x2,y2,c=P,sw=1,dash=None):return f'<path d="M{x1:g} {y1:g}L{x2:g} {y2:g}" fill="none" stroke="{c}" stroke-width="{sw:g}"'+(f' stroke-dasharray="{dash}"' if dash else '')+'/>'
def text(t,x,y,size=18,c=D,bold=False,spacing=0):
 font=BOLD if bold else FONT; gs=font.getGlyphSet();cm=font.getBestCmap();upm=font['head'].unitsPerEm;scale=size/upm
 pen=SVGPathPen(gs);xp=0
 for ch in str(t):
  g=cm.get(ord(ch),'.notdef');gs[g].draw(TransformPen(pen,(scale,0,0,-scale,x+xp,y)))
  xp+=font['hmtx'][g][0]*scale+spacing
 return f'<g aria-label="{esc(t)}" fill="{c}"><path d="{pen.getCommands()}"/></g>'
def para(lines,x,y,size=20,c=D,leading=32,bold=False):return ''.join(text(t,x,y+i*leading,size,c,bold) for i,t in enumerate(lines))
def symbol(mode='color'):
 return ''.join(f'<path id="{n}" d="{pathpoly(pts)}" fill="{cc if mode=="color" else mode}"/>' for n,pts,cc in PLANES)
def word(c=D,seal=False):
 out=[]
 for i,ch in enumerate('FORTOP'):
  dd=GLYPHS[ch]
  if seal and i==1:
   # First O is a solid bowl whose negative counter is the exact ASCENSO symbol.
   dd=GLYPHS['O'].split(' M31')[0]
   for _,pts,_ in PLANES:
    dd+=' '+pathpoly([(23+x*.295,21.68+y*.295) for x,y in pts])
  out.append(f'<path id="letra-{ch.lower()}-{i+1}" d="{dd}" transform="translate({POS[i]} 0)" fill="{c}" fill-rule="evenodd"/>')
 return '<g id="lettering-solido">'+''.join(out)+'</g>'
def horizontal(mode='color'):
 return '<g id="simbolo-ascenso">'+symbol(mode)+'</g>'+tr(word(D if mode=='color' else mode),272,56,.8)
def svg(w,h,body,title,desc='',view=None):
 counts={}
 def unique(m):
  old=m.group(1);counts[old]=counts.get(old,0)+1
  return 'id="'+old+('' if counts[old]==1 else '-'+str(counts[old]))+'"'
 body=re.sub(r'id="([^"]+)"',unique,body)
 return f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="{w}" height="{h}" viewBox="{view or f"0 0 {w} {h}"}" role="img" aria-labelledby="title desc"><title id="title">{esc(title)}</title><desc id="desc">{esc(desc or title)}</desc>{body}</svg>\n'
def save(rel,w,h,body,title,desc='',view=None):
 p=ROOT/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(svg(w,h,body,title,desc,view),encoding='utf-8');return p

def logo_files():
 variants=[('color-transparente','color',None),('color-ivory','color',I),('color-honeydew','color',H),('mono-shadow',D,None),('mono-pine',P,None),('mono-ivory',I,None),('mono-honeydew',H,None),('inverso-shadow',I,D),('inverso-pine',I,P)]
 for name,mode,bg in variants:
  for folder,key,ww,hh,content in [
   ('01_ISOTIPO','isotipo',224,192,symbol(mode)),
   ('02_LOGOTIPO','logotipo',WW,100,word(D if mode=='color' else mode)),
   ('03_IMAGOTIPO','imagotipo',864.8,192,horizontal(mode))]:
   pad=24 if key!='logotipo' else 20
   save(f'{folder}/FORTOP_{key}_{name}.svg',ww+2*pad,hh+2*pad,(rect(0,0,ww+2*pad,hh+2*pad,bg) if bg else '')+tr(content,pad,pad),f'FORTOP · {key} · {name}','SVG vectorial nativo. Lettering original convertido en curvas; no requiere fuentes. Paleta corporativa exacta.')
 for name,c,bg in [('shadow',D,None),('pine',P,None),('ivory',I,None),('inverso-shadow',I,D),('inverso-pine',I,P)]:
  save(f'04_ISOLOGO/FORTOP_isologo_tallado_{name}.svg',781,140,(rect(0,0,781,140,bg) if bg else '')+tr(word(c,True),20,20),'FORTOP · Isologo tallado','Firma secundaria para gran formato. ASCENSO es el contragrafismo de la primera O. Ancho mínimo de arte: 360 px.')
 # Tight masters are geometrically exact, without padding or export decoration.
 for name,w,h,b in [('isotipo',224,192,symbol()),('logotipo',WW,100,word()),('imagotipo',864.8,192,horizontal()),('isologo',WW,100,word(D,True))]:
  save(f'00_MAESTROS/FORTOP_{name}_master.svg',w,h,b,'FORTOP · '+name+' · maestro','Área ajustada al dibujo. Usar las versiones con margen para colocación directa.')

def digital():
 for name,bg,fg in [('shadow',D,I),('pine',P,I),('honeydew',H,D),('ivory',I,P)]:
  b=rect(0,0,512,512,bg)+tr(symbol(fg),104,126,304/224)
  save(f'05_DIGITAL/app-icons/FORTOP_app_{name}_512.svg',512,512,b,'FORTOP · App icon '+name,'Fondo cuadrado sin esquinas integradas; el sistema operativo aplica su máscara. Símbolo dentro de una zona segura de 304 × 261 px.')
  save(f'05_DIGITAL/avatares/FORTOP_avatar_{name}_1024.svg',1024,1024,rect(0,0,1024,1024,bg)+tr(symbol(fg),272,306,480/224),'FORTOP · Avatar '+name,'Contenido central seguro para recorte circular o cuadrado.')
 for n in [16,32,48,64]:
  save(f'05_DIGITAL/favicon/FORTOP_favicon_{n}.svg',n,n,rect(0,0,n,n,P,max(1,n*.18))+tr(symbol(I),n*.15,n*.20,n*.7/224),'FORTOP · Favicon '+str(n),'Reproducción monocroma del símbolo ASCENSO. Uso excepcional en interfaces pequeñas.')
 for name,c in [('shadow',D),('ivory',I)]:
  save(f'05_DIGITAL/marca-de-agua/FORTOP_watermark_{name}.svg',912.8,240,f'<g opacity="0.08">{tr(horizontal(c),24,24)}</g>','FORTOP · Marca de agua '+name,'Marca de agua al 8%; no usar como identificación principal.')
 (ROOT/'05_DIGITAL/site.webmanifest').write_text(json.dumps({'name':'FORTOP','short_name':'FORTOP','display':'standalone','background_color':I,'theme_color':P,'icons':[{'src':'app-icons/FORTOP_app_pine_192.png','sizes':'192x192','type':'image/png','purpose':'any'},{'src':'app-icons/FORTOP_app_pine_512.png','sizes':'512x512','type':'image/png','purpose':'any'},{'src':'app-icons/FORTOP_app_pine_maskable_512.png','sizes':'512x512','type':'image/png','purpose':'maskable'}]},indent=2)+'\n')
 (ROOT/'05_DIGITAL/integracion-web.txt').write_text('Copiar la carpeta 05_DIGITAL manteniendo las rutas. En el <head>:\n<link rel="icon" href="/05_DIGITAL/favicon/FORTOP_favicon_32.svg" type="image/svg+xml">\n<link rel="icon" href="/05_DIGITAL/favicon/favicon.ico" sizes="any">\n<link rel="apple-touch-icon" href="/05_DIGITAL/app-icons/apple-touch-icon.png">\n<link rel="manifest" href="/05_DIGITAL/site.webmanifest">\n<meta name="theme-color" content="#2B4F42">\n\nLos SVG del logo no requieren fuentes. Usar alt="FORTOP" cuando identifique la marca.\n')
 # Separate maskable icon, full artwork inside the central 80% diameter circle.
 save('05_DIGITAL/app-icons/FORTOP_app_pine_maskable_512.svg',512,512,rect(0,0,512,512,P)+tr(symbol(I),116,136,280/224),'FORTOP · Maskable icon','Símbolo contenido dentro de la zona circular segura del 80%.')

def head(k,title,num,bg=I):
 fg=I if bg in [D,P] else D
 return rect(0,0,1440,900,bg)+text('FORTOP  /  IDENTIDAD VISUAL',64,53,15,fg,bold=True,spacing=1)+text(k.upper(),64,131,16,fg,spacing=2)+text(title,64,196,44,fg,bold=True)+line(64,838,1376,838,fg)+text('ASCENSO + SÓLIDO',64,871,13,fg,spacing=1)+text(f'20.10.2026    /    {num:02}',1177,871,13,fg)
def page(n,name,body):save(f'07_MANUAL/paginas-svg/{n:02}_{name}.svg',1440,900,body,'FORTOP · Manual · '+name)

def manual():
 b=rect(0,0,1440,900,D)+text('FORTOP  /  BRAND SYSTEM',64,58,16,I,bold=True,spacing=2)+text('IDENTIDAD VISUAL',64,174,18,H,spacing=3)
 b+=tr(horizontal(I),120,280,1.36)+line(64,731,1376,731,H)+text('Ascenso en la forma.',64,785,32,I,bold=True)+text('Solidez en cada detalle.',64,828,32,H)+text('MANUAL DE MARCA   /   01.0',1074,789,14,I)+text('20 OCTUBRE 2026',1074,821,14,H)
 page(1,'portada',b)
 b=head('01 / El sistema','Una identidad, cuatro piezas.',2)
 b+=para(['Símbolo ASCENSO + lettering SÓLIDO + disposición horizontal ASCENSO.', 'La geometría se reconstruye a mano a partir de las tres referencias seleccionadas.'],64,244,20,P)
 for x,y,w,h,label,sub,content,tx,ty,ss in [
  (64,306,380,444,'01 / ISOTIPO','ASCENSO',symbol(),141,365,1),
  (468,306,908,200,'02 / LOGOTIPO','SÓLIDO',word(),506,332,1.05),
  (468,530,908,220,'03 / IMAGOTIPO','Firma principal',horizontal(),625,544,.69)]:
  b+=rect(x,y,w,h,H)+tr(content,tx,ty,ss)+text(label,x+24,y+h-50,14,D,bold=True)+text(sub,x+24,y+h-24,14,P)
 page(2,'sistema',b)
 b=head('02 / Símbolo','Cuatro planos. Un ascenso.',3)
 sx,sy,sc=109,290,2.15
 for xx in range(0,225,16):b+=line(sx+xx*sc,sy,sx+xx*sc,sy+192*sc,H)
 for yy in range(0,193,16):b+=line(sx,sy+yy*sc,sx+224*sc,sy+yy*sc,H)
 b+=tr(symbol(),sx,sy,sc)
 b+=line(sx,sy-25,sx+224*sc,sy-25,P)+text('224 u',sx+205,sy-40,17,P)
 b+=line(sx-25,sy,sx-25,sy+192*sc,P)+text('192 u',sx+190,sy+192*sc+38,17,P)
 b+=text('Una silueta fiel a ASCENSO.',738,296,28,D,True)
 b+=para(['Dos planos interiores de distinta altura y dos alas bajas.', 'El plano interior izquierdo define la cota máxima.', 'Los cuatro contornos son piezas editables independientes.'],738,343,18,P,30)
 b+=text('GEOMETRÍA MAESTRA',738,478,14,D,True,1)
 b+=para(['Caja del símbolo                  224 × 192 u', 'Separaciones interiores        16 / 12 / 14 u', 'Corte superior central           46 × 66 u', 'Grosor de referencia x           24 u'],738,518,19,D,35)
 b+=para(['Las pendientes reproducen la referencia: no se fuerzan', 'a 45°. Las asimetrías de altura forman parte del símbolo.', 'No añadir contornos, radios ni uniones entre planos.'],738,702,17,P,28)
 page(3,'construccion-isotipo',b)
 b=head('03 / Lettering','SÓLIDO, dibujado letra a letra.',4)
 b+=tr(word(),90,275,1.68)+line(90,275,1335,275,P)+line(90,443,1335,443,P)
 b+=text('741 u / anchura total',90,477,16,P)+text('100 u / altura de mayúscula',1008,477,16,P)
 for x,ch in [(90,'F'),(500,'O'),(910,'R')]:
  b+=rect(x,523,360,236,H)+tr(f'<path d="{GLYPHS[ch]}" fill="{D}" fill-rule="evenodd"/>',x+25,547,1.1)
  desc={'F':['Astas: 24 u','Barras: 22 u','Corte abierto y neto.'],'O':['Asta lateral: 24 u','Barra: 23 u','Curvas: módulos 25 / 7 u.'],'R':['Bucle compartido con P','Diagonal de salida propia','Empalme continuo.']}[ch]
  b+=para(desc,x+161,568,14,D,27)
 b+=text('Orígenes de letra: F 0 / O 115 / R 246 / T 375 / O 500 / P 631. Espaciado óptico, no tracking automático.',90,797,17,P)
 page(4,'lettering',b)
 b=head('04 / Firma principal','Proporción y espacio para respirar.',5)
 # clearspace shown using one x = 24 u at the native scale 1.1
 xx,yy,ss=244,331,1.1
 b+=rect(xx-24*ss,yy-24*ss,(864.8+48)*ss,240*ss,H)
 b+=tr(horizontal(),xx,yy,ss)
 for a,bb,cc,dd in [(xx,yy,xx+864.8*ss,yy),(xx,yy+192*ss,xx+864.8*ss,yy+192*ss)]:b+=line(a,bb,cc,dd,P,1,'4 6')
 b+=line(xx+272*ss,yy+56*ss,xx+864.8*ss,yy+56*ss,P,1,'4 6')+line(xx+272*ss,yy+136*ss,xx+864.8*ss,yy+136*ss,P,1,'4 6')
 b+=line(xx+224*ss,yy+100,xx+272*ss,yy+100,P)+text('48 u',xx+220*ss,yy+84,14,P)
 b+=text('x',xx-20*ss,yy-7,18,P,bold=True)
 b+=para(['Símbolo: 224 × 192 u', 'Palabra: 592,8 × 80 u', 'Separación: 48 u (2x)'],96,676,22,D,35)
 b+=para(['Centro de palabra a y=96 u, igual al centro de la caja del símbolo.', 'Conservar al menos x=24 u libres por lado en isotipo e imagotipo.', 'En logotipo e isologo, el margen mínimo es de 20 u por lado.'],626,678,18,P,34)
 page(5,'composicion-y-seguridad',b)
 b=head('05 / Color','Cuatro colores. Valores cerrados.',6)
 colors=[('Shadow Grey',D,'46, 40, 42'),('Pine Teal',P,'43, 79, 66'),('Ivory',I,'255, 255, 243'),('Honeydew',H,'224, 239, 218')]
 for j,(name,c,rgb) in enumerate(colors):
  x=64+j*334;b+=rect(x,266,310,260,c,0,stroke=P if c==I else None)+text(name,x,568,22,D,True)+text(c,x,606,23,P)+text('RGB '+rgb,x,637,16,P)
 b+=text('Combinaciones de texto y fondo',64,708,20,D,True)
 def lum(c):
  vs=[int(c[k:k+2],16)/255 for k in (1,3,5)];vs=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in vs];return sum(a*b for a,b in zip(vs,[.2126,.7152,.0722]))
 pairs=[(D,I,'Shadow / Ivory'),(P,I,'Pine / Ivory'),(D,H,'Shadow / Honeydew'),(P,H,'Pine / Honeydew')]
 for j,(fg,bg,label) in enumerate(pairs):
  ratio=(max(lum(fg),lum(bg))+.05)/(min(lum(fg),lum(bg))+.05)
  b+=text(label,64+j*334,751,16,P)+text(f'{ratio:.2f}:1',64+j*334,788,24,D,True)
 page(6,'paleta',b)
 b=head('06 / Versiones','La misma geometría en cada fondo.',7)
 specs=[(I,'color','BICOLOR / IVORY'),(H,'color','BICOLOR / HONEYDEW'),(D,I,'INVERSO / SHADOW'),(P,I,'INVERSO / PINE'),(I,D,'MONOCROMO / SHADOW'),(I,P,'MONOCROMO / PINE')]
 for j,(bg,mode,label) in enumerate(specs):
  x=64+(j%2)*668;y=250+(j//2)*178
  b+=rect(x,y,644,156,bg,stroke=H if bg==I else None)+tr(horizontal(mode),x+106,y+12,.50)+text(label,x+25,y+135,12,I if bg in [D,P] else D,True,1)
 b+=text('Sobre fondos oscuros se usa una sola tinta clara. Evitar verde sobre carbón por su bajo contraste.',64,816,17,P)
 page(7,'versiones',b)
 b=head('07 / Reducción','Una firma para cada escala.',8)
 rows=[('ISOTIPO','24 px / 8 mm','Recomendado: 32 px o más.',symbol(),224,192,24),('LOGOTIPO','120 px / 25 mm','Letra sin símbolo.',word(),WW,100,120),('IMAGOTIPO','160 px / 45 mm','Firma principal.',horizontal(),864.8,192,160),('ISOLOGO TALLADO','360 px / 60 mm','Reservado a usos de gran formato.',word(D,True),WW,100,360)]
 for j,(label,mini,note,content,w,h,sw) in enumerate(rows):
  y=264+j*129;b+=line(64,y+99,1376,y+99,H)+text(label,64,y+24,16,D,True)+text(mini,348,y+24,20,P)+text(note,348,y+59,16,P)+tr(content,866,y+12,sw/w)
 b+=para(['Los tamaños se refieren al ancho del dibujo, salvo el isotipo (altura).', 'Favicon: excepción de 16 px, siempre monocromo; emplear los PNG e ICO preparados.', 'No colocar textos, marcos o fotografías dentro del área de protección.'],64,794,16,P,19)
 # Fix isotipo sizing to its height, not width.
 b=b.replace('scale(0.107143)','scale(0.125)')
 page(8,'escalas',b)
 b=head('08 / Criterios de uso','La consistencia también es diseño.',9)
 good=rect(64,253,627,219,H)+tr(horizontal(),111,284,.61)+text('CORRECTO',91,440,13,D,True,1)
 bad=rect(715,253,661,219,I,stroke=H)+f'<g transform="translate(762 303) scale(.61 .34)">{horizontal()}</g>'+text('NO / ESTIRAR O APLASTAR',742,440,13,D,True,1)
 good+=rect(64,496,627,219,P)+tr(horizontal(I),111,526,.61)+text('CORRECTO',91,683,13,I,True,1)
 bad+=rect(715,496,661,219,D)+tr(horizontal(P),762,526,.61)+text('NO / VERDE SOBRE CARBÓN',742,683,13,I,True,1)
 b+=good+bad+para(['Tampoco girar las piezas, cerrar las separaciones, cambiar el lettering, añadir sombras o usar otros colores.', 'No reconstruir la palabra con una fuente del sistema. Usar siempre los trazados incluidos.'],64,764,18,P,29)
 page(9,'usos',b)
 b=head('09 / Firma integrada','ASCENSO tallado en la primera O.',10,D)
 b+=tr(word(I,True),90,311,1.68)
 b+=para(['Una firma secundaria: el símbolo forma el contragrafismo de la primera O.', 'La letra y el emblema comparten un solo trazado compuesto con huecos transparentes.', 'El resto de SÓLIDO mantiene sus proporciones originales.'],90,568,23,H,37)
 b+=text('360 px mínimo / 60 mm',90,754,24,I,True)+text('Uso: portadas, cartelería y piezas de gran formato.',650,754,20,H)
 page(10,'isologo',b)
 b=head('10 / Aplicaciones','Una familia lista para usar.',11)
 # Vector business cards, avatar, icon, and cover.
 b+=rect(64,255,504,318,D)+tr(horizontal(I),105,352,.48)+text('TARJETA / ANVERSO',88,549,12,H,True,1)
 b+=rect(592,255,244,244,P,36)+tr(symbol(I),645,317,.62)
 b+=rect(860,255,244,244,H,122)+tr(symbol(D),927,326,.49)
 b+=rect(1128,255,248,244,I,stroke=H)+tr(symbol(P),1185,316,.61)
 b+=text('APP ICON',592,534,13,P,True,1)+text('AVATAR',860,534,13,P,True,1)+text('SÍMBOLO',1128,534,13,P,True,1)
 b+=rect(592,584,784,205,H)+tr(word(),631,634,.87)+text('CABECERA / PORTADA',617,764,12,P,True,1)
 b+=para(['Todas estas aplicaciones se entregan como SVG.', 'Las imágenes PNG proceden de esos mismos vectores.', 'Las tarjetas y el A4 son plantillas de identidad:', 'añadir contenido en una copia del archivo.'],64,635,18,P,31)
 page(11,'aplicaciones',b)
 b=head('11 / Entrega','Del maestro a la aplicación.',12)
 items=[('00_MAESTROS','Geometría ajustada al dibujo, sin márgenes.'),('01 / 02 / 03','Isotipo, logotipo e imagotipo con margen de seguridad.'),('04_ISOLOGO','Firma tallada secundaria para usos grandes.'),('05_DIGITAL','Iconos, avatares, favicon, manifest y marcas de agua.'),('06_APLICACIONES','Tarjetas, A4, portada y recursos gráficos.'),('07_MANUAL / 08_PALETA','Manual vectorial, lámina de marca y colores exactos.'),('09_PREVISUALIZACIONES','PNG con el mismo nombre que su SVG de origen.'),('10_FUENTES / 99_REFERENCIAS','Código editable, geometría y referencias originales.')]
 for j,(a,z) in enumerate(items):
  y=271+j*60;b+=text(a,64,y,18,D,True)+text(z,482,y,18,P)+line(64,y+22,1376,y+22,H)
 b+=text('Elegir la versión por fondo. Escalar proporcionalmente. Conservar el área de seguridad.',64,799,18,P)
 page(12,'entrega',b)

def apps():
 # Business card artwork is actual size, SVG dimensions in mm. No fake contact details.
 p=save('06_APLICACIONES/tarjetas/FORTOP_tarjeta_anverso_85x55mm.svg',850,550,rect(0,0,850,550,D)+tr(horizontal(I),82,192,.793),'FORTOP · Tarjeta · anverso','Formato terminado 85 × 55 mm. Sin sangrado. Añadir sangrado en el documento de imprenta.')
 p.write_text(p.read_text().replace('width="850" height="550"','width="85mm" height="55mm"'))
 p=save('06_APLICACIONES/tarjetas/FORTOP_tarjeta_reverso_85x55mm.svg',850,550,rect(0,0,850,550,I)+tr(symbol(),62,58,.52)+tr(word(),62,420,.49)+rect(0,530,850,20,P),'FORTOP · Tarjeta · reverso','Plantilla sin datos de contacto; zona libre a la derecha para añadir los datos reales. Formato 85 × 55 mm sin sangrado.')
 p.write_text(p.read_text().replace('width="850" height="550"','width="85mm" height="55mm"'))
 save('06_APLICACIONES/portadas/FORTOP_portada_1920x1080.svg',1920,1080,rect(0,0,1920,1080,D)+tr(horizontal(I),150,390,1.75)+line(150,900,1770,900,H)+text('FORTOP',150,968,19,H,True,2),'FORTOP · Portada 16:9','Plantilla de portada sin título de proyecto. Incorporar contenido real en la zona inferior.')
 save('06_APLICACIONES/social/FORTOP_social_1200x630.svg',1200,630,rect(0,0,1200,630,H)+tr(horizontal(),115,209,1.12)+rect(0,610,1200,20,P),'FORTOP · Cabecera social 1200 × 630')
 b=rect(0,0,794,1123,I)+tr(horizontal(),58,55,.41)+line(58,164,736,164,P,1)+f'<g opacity="0.05">{tr(symbol(P),448,684,1.1)}</g>'+line(58,1050,736,1050,P,1)+tr(word(),58,1071,.16)
 p=save('06_APLICACIONES/papeleria/FORTOP_hoja_A4.svg',794,1123,b,'FORTOP · Hoja A4','Plantilla vectorial vacía; contenido editable. Sin información de contacto ficticia.')
 p.write_text(p.read_text().replace('width="794" height="1123"','width="210mm" height="297mm"'))
 b=rect(0,0,1200,800,H)
 for y in [-70,165,400,635]:
  for x in [-80,240,560,880,1200]:b+=f'<g opacity="0.12">{tr(symbol(P),x+(80 if y in [165,635] else 0),y,.65)}</g>'
 save('06_APLICACIONES/recursos/FORTOP_patron_ascenso.svg',1200,800,b,'FORTOP · Patrón ASCENSO','Aplicación gráfica secundaria. No usar el patrón como marca de identificación.')

def sheet():
 b=rect(0,0,1600,1940,I)+rect(0,0,1600,610,D)
 b+=text('FORTOP  /  IDENTIDAD VISUAL',70,61,17,H,True,2)+text('ASCENSO + SÓLIDO',1227,61,14,H)
 b+=tr(horizontal(I),167,211,1.46)+text('Geometría precisa. Presencia sólida.',70,555,26,I)
 b+=text('01 / SÍMBOLO',70,685,15,P,True,2)+text('02 / LETTERING',620,685,15,P,True,2)
 b+=tr(symbol(),150,733,1.2)+tr(word(),620,792,1.16)
 b+=line(70,1034,1530,1034,P,1)
 b+=text('03 / FIRMA PRINCIPAL',70,1093,15,P,True,2)+tr(horizontal(),70,1148,1.02)
 for j,(bg,fg) in enumerate([(D,I),(P,I),(H,D)]):
  x=1044+j*166;b+=rect(x,1151,145,145,bg,22)+tr(symbol(fg),x+32,1190,.36)
 b+=text('04 / PALETA CORPORATIVA',70,1454,15,P,True,2)
 for j,(name,cc) in enumerate([('Shadow Grey',D),('Pine Teal',P),('Ivory',I),('Honeydew',H)]):
  x=70+j*370;b+=rect(x,1490,350,160,cc,stroke=P if cc==I else None)+text(name,x,1694,20,D,True)+text(cc,x,1730,19,P)
 b+=line(70,1806,1530,1806,P)+text('SVG NATIVOS  /  LETTERING ORIGINAL  /  CUATRO COLORES EXACTOS',70,1866,15,P,True,1)+text('20.10.2026',1383,1866,14,P)
 save('07_MANUAL/FORTOP_brand_sheet.svg',1600,1940,b,'FORTOP · Brand sheet','Resumen del sistema de identidad. Todo el contenido es vectorial. Previsualización renderizada desde este SVG.')

logo_files();digital();manual();apps();sheet()
# Preserve the exact approved palette; regenerate a new sheet without the unapproved grey reference stroke.
pal=ROOT/'08_PALETA';pal.mkdir(exist_ok=True)
for name in ['FORTOP_COLORES.css','FORTOP_PALETA.json']:
 shutil.copy(REF/'02_PALETA'/name,pal/name)
b=rect(0,0,1600,600,I)+text('FORTOP / PALETA CORPORATIVA',64,75,26,D,True)
for j,(n,c,rgb) in enumerate([('Shadow Grey',D,'46, 40, 42'),('Pine Teal',P,'43, 79, 66'),('Ivory',I,'255, 255, 243'),('Honeydew',H,'224, 239, 218')]):
 x=64+j*375;b+=rect(x,124,350,280,c,stroke=P if c==I else None)+text(n,x,454,24,D,True)+text(c,x,496,24,P)+text('RGB '+rgb,x,535,17,P)
save('08_PALETA/FORTOP_paleta.svg',1600,600,b,'FORTOP · Paleta exacta')
geo={'brand':'FORTOP','version':'1.0','date':'2026-10-20','palette':C,'symbol':{'width':224,'height':192,'protection':24,'planes':[{'id':n,'points':pts,'fill':c}for n,pts,c in PLANES]},'wordmark':{'width':WW,'height':100,'protection':20,'glyphs':GLYPHS,'word':'FORTOP','origins':POS},'horizontal':{'width':864.8,'height':192,'wordmark_x':272,'wordmark_y':56,'wordmark_scale':.8,'protection':24},'isologo':{'usage':'secondary large format','first_o_symbol_scale':.295,'first_o_symbol_origin':[23,21.68]}}
(ROOT/'00_MAESTROS/FORTOP_geometria.json').write_text(json.dumps(geo,ensure_ascii=False,indent=2)+'\n')
print('Generated',len(list(ROOT.rglob('*.svg'))),'native SVGs at',ROOT)
