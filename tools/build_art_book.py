"""Build the showcase book, reference gallery and portable art pack."""
import argparse
import html
import io
import json
import re
from pathlib import Path
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
REFS = ROOT / 'preproduction/model-references'
OUT = ROOT / 'output/pdf'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1008, 720
NAVY, INK, CREAM = '#082D3B', '#143A46', '#F4F0E7'
GOLD, TEAL, MUTE = '#BE9656', '#287E8C', '#667C80'
for name, filename in [('Display','georgia.ttf'),('DisplayBold','georgiab.ttf'),
                       ('Body','calibri.ttf'),('Bold','calibrib.ttf'),('Light','calibril.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(Path('C:/Windows/Fonts')/filename)))

def clean(s):
    return s.replace('\u2014',' - ').replace('\u2013','-').replace('\u2011','-')

def text(c, x, y, s, size=12, font='Body', color=INK):
    c.setFillColor(HexColor(color)); c.setFont(font,size); c.drawString(x,y,clean(s))

def paragraph(c, x, y, s, width, size=14, leading=21, color=INK, font='Body'):
    for p in s.split('\n'):
        line=''
        for word in clean(p).split():
            test=(line+' '+word).strip()
            if pdfmetrics.stringWidth(test,font,size)>width and line:
                text(c,x,y,line,size,font,color); y-=leading; line=word
            else: line=test
        if line: text(c,x,y,line,size,font,color); y-=leading
        y-=leading*.35
    return y

cache={}
def picture(c, path, x, y, width, height, fill=False):
    path=Path(path)
    if path not in cache:
        im=Image.open(path).convert('RGB')
        data=io.BytesIO(); im.save(data,format='JPEG',quality=93,subsampling=0,optimize=True)
        cache[path]=(ImageReader(data),im.size)
    reader,(iw,ih)=cache[path]
    scale=max(width/iw,height/ih) if fill else min(width/iw,height/ih)
    dw,dh=iw*scale,ih*scale
    c.saveState()
    if fill:
        p=c.beginPath(); p.rect(x,y,width,height); c.clipPath(p,stroke=0)
    c.drawImage(reader,x+(width-dw)/2,y+(height-dh)/2,dw,dh)
    c.restoreState()

def background(c,color=CREAM):
    c.setFillColor(HexColor(color));c.rect(0,0,W,H,fill=1,stroke=0)

def footer(c,label,dark=False):
    color='#99B4B9' if dark else MUTE
    c.setStrokeColor(HexColor('#315563' if dark else '#D6D7CC'))
    c.setLineWidth(.5);c.line(38,38,W-38,38)
    text(c,38,22,'WIZARDS ON A BOAT  /  '+label.upper(),8,'Bold',color)
    c.setFont('Body',9);c.setFillColor(HexColor(color));c.drawRightString(W-38,22,f'{c.getPageNumber():02d}')

def divider(c,number,title,subtitle,path,key):
    background(c,NAVY); c.bookmarkPage(key);c.addOutlineEntry(title,key,0)
    picture(c,path,430,75,540,568)
    text(c,42,630,'CHAPTER '+number,11,'Bold',GOLD)
    yy=535
    for part in title.split('\n'):
        text(c,42,yy,part,43,'Display',CREAM);yy-=55
    c.setStrokeColor(HexColor(GOLD));c.setLineWidth(1.5);c.line(42,yy-5,120,yy-5)
    paragraph(c,42,yy-50,subtitle,330,17,25,'#BAD0D0','Light')
    footer(c,'Concept collection',True);c.showPage()

def board(c,item,section):
    background(c,NAVY)
    text(c,38,H-35,section.upper(),9,'Bold',GOLD)
    text(c,38,H-65,item['title'],23,'Display',CREAM)
    picture(c,ROOT/'preproduction'/item['file'],38,82,W-76,H-167)
    paragraph(c,38,64,item['description'],W-76,10,13,'#BCD0D1')
    footer(c,section,True);c.showPage()

def reference_pair(c,jobs,section):
    background(c)
    text(c,38,H-35,'THE ASSET COLLECTION / '+section.upper(),9,'Bold',TEAL)
    card_width=W-76 if len(jobs)==1 else (W-96)/2
    for i,j in enumerate(jobs):
        x=38+i*(card_width+20)
        c.setFillColor(HexColor('#E5E9E7'));c.roundRect(x,144,card_width,520,7,fill=1,stroke=0)
        picture(c,REFS/(j['id']+'.png'),x+9,153,card_width-18,502)
        title_size=min(21,21*(card_width/pdfmetrics.stringWidth(clean(j['title']),'Display',21)))
        text(c,x,115,j['title'],title_size,'Display')
        text(c,x,91,j.get('caption',j['category']+' / complete subject'),11,'Body',MUTE)
        text(c,x,70,j['id']+'.png',9,'Body',MUTE)
    footer(c,'Single-view model references');c.showPage()

def build(draft=False):
    raw=(ROOT/'preproduction/manifest.js').read_text(encoding='utf-8-sig')
    concepts=json.loads(raw[raw.index('['):raw.rindex(']')+1])
    by_id={x['id'].split('-')[0]:x for x in concepts}
    manifest=json.loads((REFS/'generation-manifest.json').read_text(encoding='utf-8-sig'))
    jobs=[{'id':'wizard','title':'The seafaring wizard','category':'Characters','board':'01-wizard.png','status':'generated'}]
    jobs += [j for j in manifest['jobs'] if j['status']!='consolidated']
    missing=[j['id'] for j in jobs if not (REFS/(j['id']+'.png')).exists()]
    if missing and not draft:raise RuntimeError('Missing references: '+', '.join(missing))
    jobs=[j for j in jobs if (REFS/(j['id']+'.png')).exists()]
    path=OUT/('Wizards-on-a-Boat-Concept-Art-Book-DRAFT.pdf' if draft else 'Wizards-on-a-Boat-Concept-Art-Book.pdf')
    c=canvas.Canvas(str(path),pagesize=(W,H),pageCompression=1)
    c.setTitle('Wizards on a Boat - Concept Art Book');c.setAuthor('Wizards on a Boat')
    c.setSubject('Approved visual direction and single-view model references')
    c.setViewerPreference('DisplayDocTitle','true')
    # Cover.
    background(c,NAVY);picture(c,ROOT/'preproduction/art/00-voyage.png',350,0,W-350,H,fill=True)
    c.setFillColor(HexColor(NAVY));c.rect(0,0,370,H,fill=1,stroke=0)
    text(c,42,650,'THE CONCEPT COLLECTION',11,'Bold',GOLD)
    for y,line in [(516,'Wizards'),(447,'on a Boat')]:text(c,42,y,line,52,'Display',CREAM)
    c.setStrokeColor(HexColor(GOLD));c.setLineWidth(1.5);c.line(44,400,124,400)
    paragraph(c,44,351,'Bright seas.\nCurious shores.\nMagic worth sharing.',284,24,34,'#C7D8D5','Light')
    text(c,44,101,'ART DIRECTION / WORLD / BESTIARY',9,'Bold',GOLD)
    text(c,44,65,'VOLUME 01  -  SEPTEMBER 2026',10,'Body','#A8C1C5');c.showPage()
    # Introduction and contents, chapter destinations resolve later.
    background(c);text(c,42,655,'A WORLD WORTH SAILING',10,'Bold',TEAL)
    text(c,42,580,'Bring a crew.',37,'Display');text(c,42,530,'Make your own magic.',37,'Display')
    paragraph(c,44,465,'A first-person multiplayer adventure about wizards sharing a boat on an untamed sea. Sail between island biomes, descend into living underwater habitats, and swim up waterfalls to the islands above.',423,18,27)
    paragraph(c,44,325,'Craft spells from discoveries, use magic to move the world, and return to a welcoming harbour with the stories and treasures of a voyage.',423,17,25)
    paragraph(c,44,180,'This book presents visual direction: the approved concept boards and a new collection of isolated object references. The images are concept art, not gameplay captures or finished 3D assets.',423,12,18,MUTE)
    contents=[('01','The great sea','world'),('02','Crew, craft & magic','crew'),('03','Places to discover','places'),('04','Below the surface','dungeons'),('05','A living world','bestiary'),('06','The asset collection','references')]
    for i,(num,title,key) in enumerate(contents):
        y=576-i*68;text(c,560,y,num,12,'Bold',TEAL);text(c,603,y,title,23,'Display')
        c.linkRect('',key,(555,y-15,966,y+31),relative=0,thickness=0)
        c.setStrokeColor(HexColor('#D6D7CC'));c.line(560,y-26,966,y-26)
    footer(c,'An invitation');c.showPage()
    # Original style direction, kept whole.
    c.bookmarkPage('world');c.addOutlineEntry('01 The great sea','world',0)
    board(c,{'title':'The Great Sea','file':'references/great-sea-style-board.png','description':'The original visual compass: cobalt water, broken ivory foam, bright skies and warm stone.'},'01 / The great sea')
    board(c,by_id['00'],'01 / The great sea')
    divider(c,'02','Crew, craft\n& magic','A shared vessel. An irreplaceable spellbook. Useful tools for a journey that belongs to the crew.',REFS/'wizard.png','crew')
    for idx in ['01','02','03','22','23','24']:board(c,by_id[idx],'02 / Crew, craft & magic')
    divider(c,'03','Places to\ndiscover','A harbour to call home, coastlines to follow, and waterfalls that lead beyond the clouds.',REFS/'lighthouse.png' if (REFS/'lighthouse.png').exists() else ROOT/'preproduction/art/04-starter-island.png','places')
    for idx in ['04','05','06','07','08','25']:board(c,by_id[idx],'03 / Places to discover')
    divider(c,'04','Below the\nsurface','Flooded stone, living roots and old observatories. Knowledge waits where the comfortable paths end.',REFS/'tide_gate.png' if (REFS/'tide_gate.png').exists() else ROOT/'preproduction/art/09-tide-vault.png','dungeons')
    for idx in ['09','10','11']:board(c,by_id[idx],'04 / Below the surface')
    divider(c,'05','A living\nworld','Creatures shaped by their habitats. Read their movements, learn their warnings, and decide when to come closer.',REFS/'ribbonwake.png','bestiary')
    for idx in [str(x) for x in range(12,22)]:board(c,by_id[idx],'05 / A living world')
    divider(c,'06','The asset\ncollection','One complete subject. One clear view. A consistent set of references for turning the approved designs into 3D.',REFS/'boat.png','references')
    categories=['Characters','Creatures','Boat & gear','Equipment','Buildings','Building kit','Nature','Dungeons']
    for category in categories:
        group=[j for j in jobs if j['category']==category]
        for start in range(0,len(group),2):reference_pair(c,group[start:start+2],category)
    background(c,NAVY);text(c,42,635,'THE NEXT HORIZON',11,'Bold',GOLD)
    text(c,42,562,'From image to voyage.',39,'Display',CREAM)
    paragraph(c,44,490,'The visual foundation is established. Complete-object references preserve each design as a coherent subject; component segmentation, mesh preparation, rigging and animation belong to the next stage of production.',530,18,28,'#C7D8D5')
    paragraph(c,44,350,'Original style direction supplied by the project creator. Concept boards and new model references created with AI-assisted image generation. This edition includes all 26 approved boards, the original style board, and '+str(len(jobs))+' selected model references.',530,14,22,'#9FBCC0')
    paragraph(c,44,223,'Names, scale notes and depicted details are design references. They do not establish finished gameplay, final model topology or animation quality.',530,12,19,'#9FBCC0')
    text(c,44,99,'WIZARDS ON A BOAT',23,'Display',CREAM);footer(c,'Volume 01',True);c.showPage();c.save()
    reader=PdfReader(path)
    expected=26
    assert len(concepts)==expected
    assert len(reader.pages)>30
    print(json.dumps({'pdf':str(path),'pages':len(reader.pages),'boards':26,'style_board':1,'references':len(jobs),'missing':missing,'bytes':path.stat().st_size}))
    # Standalone browser catalogue; original image files stay untouched.
    cards=[]
    for j in jobs:
        cards.append('<a class="card" href="'+j['id']+'.png" data-category="'+html.escape(j['category'])+'"><img loading="lazy" src="'+j['id']+'.png" alt="'+html.escape(j['title'])+'"><div><small>'+html.escape(j['category'])+'</small><h2>'+html.escape(j['title'])+'</h2><span>'+j['id']+'.png</span></div></a>')
    document='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wizards on a Boat | Model references</title><style>body{margin:0;background:#f4f0e7;color:#143a46;font:16px/1.5 system-ui}header{background:#082d3b;color:#f4f0e7;padding:55px max(5vw,24px)}h1{font:48px Georgia;margin:8px 0}header p{max-width:750px;color:#bdd0cf}.bar{padding:24px 5vw;display:flex;gap:12px}input,select{font:inherit;padding:10px;border:1px solid #becfcb;background:white;border-radius:5px}.grid{padding:0 5vw 60px;display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:24px}.card{color:inherit;text-decoration:none;background:white;border-radius:8px;overflow:hidden}.card img{display:block;width:100%;height:290px;object-fit:contain;background:#e5e9e7}.card div{padding:18px}small{color:#287e8c}h2{font:23px Georgia;margin:7px 0}span{font-size:12px;color:#667c80}.hide{display:none}</style><header><small>THE ASSET COLLECTION</small><h1>Wizards on a Boat</h1><p>Complete subjects, single views. Open an image to save or submit it to a 3D generation tool. Tripo can separate components after generation. These are image references, not finished or rigged 3D models.</p></header><div class="bar"><input id="search" placeholder="Find an asset"><select id="category"><option>All categories</option>'''+''.join('<option>'+x+'</option>' for x in categories if any(j['category']==x for j in jobs))+'''</select></div><main class="grid">'''+''.join(cards)+'''</main><script>function filter(){const q=document.querySelector('#search').value.toLowerCase(),cat=document.querySelector('#category').value;document.querySelectorAll('.card').forEach(c=>c.classList.toggle('hide',!c.innerText.toLowerCase().includes(q)||(cat!=='All categories'&&c.dataset.category!==cat)))}document.querySelector('#search').oninput=filter;document.querySelector('#category').onchange=filter;</script></html>'''
    (REFS/'index.html').write_text(document,encoding='utf-8')
    (OUT/'art-book-manifest.json').write_text(json.dumps({'pdf':path.name,'page_count':len(reader.pages),'concept_boards':[x['file'] for x in concepts],'references':[j['id']+'.png' for j in jobs]},indent=2),encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--draft',action='store_true');args=p.parse_args();build(args.draft)
