from pathlib import Path
import subprocess,concurrent.futures,sys,tempfile
from pypdf import PdfReader,PdfWriter
from PIL import Image
root=Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parent.parent.parent/'FORTOP_Brand_Kit_rebuild').resolve()
tmp=Path(tempfile.mkdtemp(prefix='fortop_pdf_'))
def export(p):
 q=tmp/(p.stem+'.pdf')
 r=subprocess.run(['inkscape',str(p),'--export-type=pdf','--export-filename='+str(q)],capture_output=True,text=True)
 if r.returncode: raise RuntimeError(r.stderr)
 if len(PdfReader(q).pages)!=1:raise RuntimeError('Wrong page count')
 return q
pages=sorted((root/'07_MANUAL/paginas-svg').glob('*.svg'))
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:qs=list(ex.map(export,pages))
w=PdfWriter()
for q in qs:w.append(str(q))
w.add_metadata({'/Title':'FORTOP - Manual de identidad visual','/Author':'FORTOP','/Subject':'ASCENSO + SÓLIDO / Paleta corporativa exacta','/Creator':'SVG nativo / exportación vectorial'})
with (root/'07_MANUAL/FORTOP_Manual_de_Marca.pdf').open('wb') as f:w.write(f)
# Multi-resolution Windows favicon, derived from vector renderings.
im=Image.open(root/'05_DIGITAL/favicon/FORTOP_favicon_64.png')
im.save(root/'05_DIGITAL/favicon/favicon.ico',format='ICO',sizes=[(16,16),(32,32),(48,48),(64,64)],append_images=[Image.open(root/f'05_DIGITAL/favicon/FORTOP_favicon_{n}.png') for n in [16,32,48]])
print('12-page vector manual and 4-size ICO exported.')
