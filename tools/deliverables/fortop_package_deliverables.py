from pathlib import Path
import os
from zipfile import ZipFile, ZIP_DEFLATED
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader, PdfWriter

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get('FORTOP_DELIVERABLES_DIR', REPOSITORY_ROOT / 'fortop-deliverables')).expanduser().resolve()
PAGES = [
    ('01-business-model-canvas/fortop-business-model-canvas', '01', 'Business Model Canvas', 'Los nueve bloques del modelo de negocio'),
    ('02-business-plan/01-propuesta-de-valor-y-modelo', '02.1', 'Propuesta de valor y modelo', 'Cliente, producto y entrada al mercado'),
    ('02-business-plan/02-costes-recursos-y-viabilidad', '02.2', 'Costes, recursos y viabilidad', 'Hipótesis de precios y escenario económico'),
    ('02-business-plan/03-implantacion-sostenibilidad-y-barreras', '02.3', 'Implantación y sostenibilidad', 'Etapas, barreras y validación del piloto'),
    ('03-arquitectura/fortop-arquitectura-actual', '03', 'Arquitectura de Fortop', 'Procesos, agentes, datos e integraciones'),
    ('04-c4/fortop-c4-01-contexto', '04.1', 'C4 · Contexto', 'Personas y sistemas externos'),
    ('04-c4/fortop-c4-02-contenedores', '04.2', 'C4 · Contenedores', 'Web, worker y PostgreSQL'),
    ('04-c4/fortop-c4-03-componentes', '04.3', 'C4 · Componentes', 'El interior del worker y su motor de agentes'),
]

# Comprobación de cada formato antes de componer los archivos conjuntos.
for stem, number, title, detail in PAGES:
    ET.parse(ROOT / (stem + '.svg'))
    with Image.open(ROOT / (stem + '.png')) as image:
        image.verify()
    pdf = PdfReader(ROOT / (stem + '.pdf'))
    assert len(pdf.pages) == 1, stem
    assert len(pdf.pages[0].extract_text()) > 100, stem

writer = PdfWriter()
for stem, number, title, detail in PAGES:
    writer.append(ROOT / (stem + '.pdf'), outline_item=number + ' · ' + title)
writer.add_metadata({
    '/Title': 'Fortop · modelo de negocio, viabilidad y arquitectura',
    '/Author': 'Fortop',
    '/Subject': 'Business Model Canvas, plan de negocio visual, arquitectura y diagramas C4',
    '/Lang': 'es-ES',
})
combined = ROOT / 'fortop-entregables.pdf'
with combined.open('wb') as file:
    writer.write(file)
assert len(PdfReader(combined).pages) == 8

# Índice visual: las miniaturas son los originales, sin rehacer su contenido.
BG, INK, MUTED, LINE, PINE = '#FFFCF0', '#222321', '#666A60', '#A6A99C', '#2B4F42'
W, H = 2520, 3820
sheet = Image.new('RGB', (W, H), BG)
draw = ImageDraw.Draw(sheet)
for y in range(16, H, 28):
    for x in range(16, W, 28):
        draw.point((x, y), fill='#E9E7DA')
font_path = '/usr/share/fonts/truetype/dejavu/'
def font(size, mono=False):
    return ImageFont.truetype(font_path + ('DejaVuSansMono.ttf' if mono else 'DejaVuSans.ttf'), size)
draw.text((82, 54), 'Fortop · entregables', font=font(66), fill=INK)
draw.text((84, 146), 'CANVAS · PLAN DE NEGOCIO · ARQUITECTURA · C4', font=font(25, True), fill=PINE)
draw.line((80, 212, W - 80, 212), fill=LINE, width=2)
left, top, gap_x, gap_y, card_w, card_h = 80, 260, 44, 38, 1158, 825
for idx, (stem, number, title, detail) in enumerate(PAGES):
    col, row = idx % 2, idx // 2
    x, y = left + col * (card_w + gap_x), top + row * (card_h + gap_y)
    draw.text((x + 2, y + 1), number, font=font(24, True), fill=PINE)
    draw.text((x + 102, y - 3), title, font=font(34), fill=INK)
    draw.text((x + 2, y + 51), detail, font=font(22), fill=MUTED)
    py, ph = y + 104, 700
    draw.rectangle((x + 6, py + 6, x + card_w + 6, py + ph + 6), fill='#E6E4D7', outline=LINE, width=1)
    draw.rectangle((x, py, x + card_w, py + ph), fill=BG, outline=LINE, width=1)
    with Image.open(ROOT / (stem + '.png')) as page:
        page = page.convert('RGB')
        page.thumbnail((card_w - 20, ph - 20), Image.Resampling.LANCZOS)
        sheet.paste(page, (x + (card_w - page.width) // 2, py + (ph - page.height) // 2))
draw.line((80, H - 89, W - 80, H - 89), fill=LINE, width=2)
draw.text((82, H - 65), '8 LÁMINAS · PNG + SVG EDITABLE + PDF', font=font(24, True), fill=MUTED)
draw.text((W - 535, H - 65), 'fortop-deliverables/', font=font(24, True), fill=PINE)
sheet.save(ROOT / '00-vista-general.png', optimize=True)

archive = ROOT / 'fortop-entregables.zip'
files = sorted(p for p in ROOT.rglob('*') if p.is_file() and p != archive)
assert not any(p.name.lower().startswith('readme') or p.suffix in {'.ppt', '.pptx'} for p in files)
with ZipFile(archive, 'w', ZIP_DEFLATED) as package:
    for path in files:
        package.write(path, Path('fortop-deliverables') / path.relative_to(ROOT))
with ZipFile(archive) as package:
    assert package.testzip() is None

print(f'{len(PAGES)} láminas verificadas · PDF conjunto de 8 páginas · {len(files)} archivos en ZIP')
print(f'PDF: {combined.stat().st_size:,} bytes · ZIP: {archive.stat().st_size:,} bytes')
