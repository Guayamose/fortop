from pathlib import Path
import os
from copy import deepcopy
import xml.etree.ElementTree as ET
import re
import math
from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ.get('FORTOP_DELIVERABLES_DIR', ROOT / 'fortop-deliverables')).expanduser().resolve()
BG = '#FFFCF0'
INK = '#222321'
MUTED = '#666A60'
LINE = '#A6A99C'
BLUE = '#245E9D'
ORANGE = '#B85D2E'
PURPLE = '#7260B4'
GREEN = '#658348'
PINE = '#2B4F42'
TONES = {
    'plain': (BG, INK, '#E4E2D6'),
    'blue': ('#E5EDED', BLUE, '#CDDEE4'),
    'orange': ('#FBE8D7', ORANGE, '#F1CEB1'),
    'purple': ('#EEE9F7', PURPLE, '#D9D0ED'),
    'green': ('#ECF1E3', GREEN, '#D8E2CB'),
    'pine': ('#E0EFDA', PINE, '#C4D8BC'),
}
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)

def tag(name): return '{%s}%s' % (NS, name)
def font(size=26, mono=False, bold=False):
    name = 'DejaVuSansMono' if mono else 'DejaVuSans'
    if bold: name += '-Bold'
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/' + name + '.ttf', int(size))
def measure(text, size=26, mono=False, bold=False):
    return font(size, mono, bold).getlength(str(text))
def wrap(text, width, size=26, mono=False, bold=False):
    lines=[]
    for paragraph in str(text).split('\n'):
        line=''
        for word in paragraph.split():
            candidate=(line+' '+word).strip()
            if line and measure(candidate,size,mono,bold)>width:
                lines.append(line); line=word
            else: line=candidate
        lines.append(line)
    return lines

class Diagram:
    def __init__(self,title,subtitle,tagline,w=2400,h=1500,page=''):
        self.w,self.h=w,h
        self.errors=[]
        self.root=ET.Element(tag('svg'),{'width':str(w),'height':str(h),'viewBox':f'0 0 {w} {h}','role':'img','aria-labelledby':'title desc'})
        ET.SubElement(self.root,tag('title'),{'id':'title'}).text='Fortop · '+title
        ET.SubElement(self.root,tag('desc'),{'id':'desc'}).text=subtitle+'. Lámina visual en español. '+tagline
        defs=ET.SubElement(self.root,tag('defs'))
        pattern=ET.SubElement(defs,tag('pattern'),{'id':'dots','width':'28','height':'28','patternUnits':'userSpaceOnUse'})
        ET.SubElement(pattern,tag('circle'),{'cx':'2','cy':'2','r':'.8','fill':'#DCDCCE','opacity':'.55'})
        for name,color in [('blue',BLUE),('orange',ORANGE),('purple',PURPLE),('green',GREEN),('ink',INK),('muted',MUTED),('pine',PINE)]:
            marker=ET.SubElement(defs,tag('marker'),{'id':'arrow-'+name,'viewBox':'0 0 10 10','refX':'8','refY':'5','markerWidth':'9','markerHeight':'9','markerUnits':'userSpaceOnUse','orient':'auto-start-reverse'})
            ET.SubElement(marker,tag('path'),{'d':'M0,0 L10,5 L0,10 Z','fill':color})
        self.rect(0,0,w,h,fill=BG,stroke='none')
        self.rect(0,0,w,h,fill='url(#dots)',stroke='none')
        self.text(80,105,title,size=54)
        self.text(82,151,subtitle,size=22,mono=True,color=MUTED)
        self.text(w-80,86,tagline.upper(),size=17,mono=True,color=MUTED,anchor='end')
        self.text(w-80,121,'FORTOP  /  '+page if page else 'FORTOP',size=19,mono=True,color=PINE,anchor='end')

    def element(self,name,**attrs):
        return ET.SubElement(self.root,tag(name),{k.replace('_','-'):str(v) for k,v in attrs.items() if v is not None})

    def rect(self,x,y,w,h,fill=BG,stroke=LINE,width=1.5,rx=0,dashed=False):
        return self.element('rect',x=x,y=y,width=w,height=h,fill=fill,stroke=stroke,stroke_width=width,rx=rx,stroke_dasharray='10 8' if dashed else None)

    def text(self,x,y,text,size=26,color=INK,mono=False,bold=False,anchor='start'):
        text=str(text)
        tw=measure(text,size,mono,bold)
        left=x if anchor=='start' else x-tw if anchor=='end' else x-tw/2
        if left < -1 or left+tw > self.w+1 or y-size < -1 or y > self.h+1:
            self.errors.append(('text_outside_page',text,left,y,tw))
        el=self.element('text',x=x,y=y,font_family='DejaVu Sans Mono, monospace' if mono else 'DejaVu Sans, Arial, sans-serif',font_size=size,font_weight='600' if bold else '400',fill=color,text_anchor=anchor)
        el.text=text
        return y+size*1.4

    def paragraph(self,x,y,text,width,size=26,line=36,color=MUTED,mono=False,bold=False):
        for row in wrap(text,width,size,mono,bold):
            self.text(x,y,row,size,color,mono,bold); y+=line
        return y

    def path(self,d,color=INK,width=1.6,fill='none',dashed=False,marker=None,start=False):
        return self.element('path',d=d,stroke=color,stroke_width=width,fill=fill,stroke_linecap='round',stroke_linejoin='round',stroke_dasharray='10 8' if dashed else None,marker_end=f'url(#arrow-{marker})' if marker else None,marker_start=f'url(#arrow-{marker})' if marker and start else None)

    def arrow(self,points,tone='blue',label=None,label_at=None,size=19,dashed=False,bidir=False):
        color=TONES.get(tone,TONES['plain'])[1] if tone!='muted' else MUTED
        self.path('M'+' L'.join(f'{x},{y}' for x,y in points),color,1.9,dashed=dashed,marker='ink' if tone=='plain' else tone,start=bidir)
        if label:
            lx,ly=label_at if label_at else ((points[0][0]+points[-1][0])/2,(points[0][1]+points[-1][1])/2-15)
            self.label(lx,ly,label,color,size)

    def label(self,x,y,text,color=MUTED,size=19):
        width=measure(text,size,True)+24
        self.rect(x-width/2,y-size-3,width,size+12,fill=BG,stroke='none')
        self.text(x,y,text,size=size,color=color,mono=True,anchor='middle')

    def pill(self,x,y,text,tone='blue',size=18):
        fill,color,_=TONES[tone]
        w=measure(text,size,True)+32
        self.rect(x,y,w,36,fill=fill,stroke=color,width=1,rx=18)
        self.text(x+w/2,y+25,text,size=size,color=color,mono=True,anchor='middle')
        return w

    def panel(self,x,y,w,h,tone='plain',depth=7,dashed=False):
        fill,color,shade=TONES[tone]
        stroke=color if tone!='plain' else LINE
        if depth and not dashed:
            self.path(f'M{x+w},{y} l{depth},{depth} v{h} l-{depth},-{depth} Z',stroke,1.4,shade)
            self.path(f'M{x},{y+h} h{w} l{depth},{depth} h-{w} Z',stroke,1.4,shade)
        self.rect(x,y,w,h,fill=fill,stroke=stroke,width=1.6,dashed=dashed)
        return color

    def boundary(self,x,y,w,h,title,subtitle=None,color=INK,dashed=False):
        self.rect(x,y,w,h,fill='none',stroke=color,width=1.5,dashed=dashed)
        width=measure(title,22,True)+28
        self.rect(x+22,y-18,width,36,fill=BG,stroke='none')
        self.text(x+35,y+7,title,size=22,color=color,mono=True)
        if subtitle: self.text(x+w-22,y+33,subtitle,size=16,color=MUTED,mono=True,anchor='end')

    def card(self,x,y,w,h,title,subtitle='',body=(),tone='plain',icon=None,title_size=31,body_size=25):
        color=self.panel(x,y,w,h,tone)
        if icon: self.icon(icon,x+35,y+43,scale=1.15,color=color)
        tx=x+70 if icon else x+26
        self.text(tx,y+49,title,title_size,color=color)
        cy=y+86
        if subtitle:
            cy=self.paragraph(x+26,cy,subtitle,w-52,size=18,line=27,color=MUTED,mono=True)+15
        else: cy=y+95
        for item in body:
            cy=self.paragraph(x+26,cy,item,w-52,size=body_size,line=body_size*1.4,color=INK)+12
        if body and cy-12>y+h-15: self.errors.append(('card_overflow',title,cy,y+h))
        return cy

    def bullet(self,x,y,text,width,size=25,tone='blue'):
        color=TONES[tone][1]
        self.element('circle',cx=x+4,cy=y-size*.32,r=3.2,fill=color)
        return self.paragraph(x+24,y,text,width-24,size=size,line=size*1.45,color=INK)+18

    def icon(self,name,x,y,scale=1,color=BLUE):
        g=ET.SubElement(self.root,tag('g'),{'transform':f'translate({x},{y}) scale({scale})','fill':'none','stroke':color,'stroke-width':'1.65','stroke-linecap':'round','stroke-linejoin':'round'})
        paths={
            'code':['M-9,-12 L-21,0 -9,12 M9,-12 L21,0 9,12 M4,-18 L-4,18'],
            'repo':['M-16,-19 h27 v38 h-27 Z M-16,11 h27 M-9,-12 v15 M-4,-12 h10'],
            'agent':['M-16,-11 h32 v26 h-32 Z M0,-19 v8 M-7,-3 v4 M7,-3 v4 M-7,8 h14 M-22,-4 v12 M22,-4 v12'],
            'check':['M-17,-13 L0,-20 17,-13 v15 Q17,16 0,23 Q-17,16 -17,2 Z M-8,1 l6,7 12,-15'],
            'lock':['M-16,-3 h32 v24 h-32 Z M-10,-3 v-8 a10,10 0 0 1 20,0 v8 M0,6 v7'],
            'chart':['M-20,-20 v40 h40 M-13,11 l9,-13 9,7 12,-21'],
            'search':['M10,10 l13,13'],
            'flow':['M-17,-13 L17,-13 M-17,-13 L0,14 M17,-13 L0,14'],
            'window':['M-22,-16 h44 v32 h-44 Z M-22,-6 h44 M-15,-11 h1 M-9,-11 h1'],
            'server':['M-21,-19 h42 v38 h-42 Z M-21,-6 h42 M-21,6 h42 M-14,-13 h1 M-14,0 h1 M-14,13 h1'],
            'brief':['M-15,-21 h23 l8,8 v34 h-31 Z M8,-21 v8 h8 M-8,-4 h16 M-8,4 h16 M-8,12 h11'],
            'leaf':['M-18,17 Q-24,-14 18,-22 Q26,12 -5,18 M-17,17 L9,-10'],
            'coins':['M-17,-8 v18 M17,-8 v18 M-17,2 Q0,14 17,2 M-17,10 Q0,23 17,10'],
            'cloud':['M-17,12 a10,10 0 0 1 -2,-20 a15,15 0 0 1 28,-4 a12,12 0 0 1 10,24 Z'],
            'person':['M-22,22 v-5 Q-22,4 0,4 Q22,4 22,17 v5'],
            'db':['M-18,-14 v27 Q0,25 18,13 v-27 M-18,-1 Q0,11 18,-1'],
            'git':['M-11,-14 v28 M-11,-3 Q12,-3 12,-14'],
        }
        for p in paths.get(name,paths['code']): ET.SubElement(g,tag('path'),{'d':p})
        if name=='db': ET.SubElement(g,tag('ellipse'),{'cx':'0','cy':'-14','rx':'18','ry':'7'})
        if name=='coins': ET.SubElement(g,tag('ellipse'),{'cx':'0','cy':'-8','rx':'17','ry':'7'})
        if name=='person': ET.SubElement(g,tag('circle'),{'cx':'0','cy':'-12','r':'10'})
        if name=='search': ET.SubElement(g,tag('circle'),{'cx':'-4','cy':'-4','r':'17'})
        if name in ['flow','git']:
            circles=[(-17,-13),(17,-13),(0,14)] if name=='flow' else [(-11,-14),(-11,14),(12,-14)]
            for cx,cy in circles: ET.SubElement(g,tag('circle'),{'cx':str(cx),'cy':str(cy),'r':'4','fill':BG})

    def metric(self,x,y,value,label,detail='',color=PINE,size=62,width=550):
        self.text(x,y,value,size=size,color=color,mono=True)
        self.text(x,y+43,label,size=26,color=INK)
        if detail: self.paragraph(x,y+80,detail,width,size=21,line=29,color=MUTED)

    def footer(self,text='',source=None):
        self.path(f'M80,{self.h-90} H{self.w-80}',LINE,1)
        self.text(82,self.h-48,text,size=17,color=MUTED,mono=True)
        logo=ET.parse(ROOT/'fortop_brand_kit/00_MAESTROS/FORTOP_logotipo_master.svg').getroot()
        logo.set('x',str(self.w-300)); logo.set('y',str(self.h-65)); logo.set('width','220'); logo.set('height','30')
        self.root.append(logo)
        if source:
            a=ET.SubElement(self.root,tag('a'),{'href':source[1]})
            el=ET.SubElement(a,tag('text'),{'x':'82','y':str(self.h-20),'font-family':'DejaVu Sans Mono, monospace','font-size':'13','fill':MUTED})
            el.text=source[0]

    def save(self,path,scale=1.5):
        import cairosvg
        path=Path(path)
        path.parent.mkdir(parents=True,exist_ok=True)
        if self.errors: raise ValueError(self.errors)
        data=ET.tostring(self.root,encoding='utf-8',xml_declaration=True)
        path.with_suffix('.svg').write_bytes(data)
        cairosvg.svg2png(bytestring=data,write_to=str(path.with_suffix('.png')),scale=scale)
        cairosvg.svg2pdf(bytestring=data,write_to=str(path.with_suffix('.pdf')))
        return path

def merge_pdfs(paths,destination):
    from pypdf import PdfWriter
    writer=PdfWriter()
    for path in paths: writer.append(str(path))
    writer.add_metadata({'/Title':'Fortop · entregables visuales','/Author':'Fortop','/Subject':'Modelo de negocio, viabilidad y arquitectura'})
    with open(destination,'wb') as f: writer.write(f)

