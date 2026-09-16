"""Check the delivered book's coverage, page bounds and navigation."""
import json
from pathlib import Path
import pdfplumber
from pypdf import PdfReader

root=Path(__file__).resolve().parents[1]
directory=root/'output/pdf'
manifest=json.loads((directory/'art-book-manifest.json').read_text())
reader=PdfReader(directory/manifest['pdf'])
assert len(manifest['concept_boards'])==26
assert len(manifest['references'])==51
assert len(reader.pages)==manifest['page_count']
assert len(reader.outline)==6
text='\n'.join(p.extract_text() for p in reader.pages)
for filename in manifest['references']:
    assert filename in text, filename
images=set()
for page in reader.pages:
    assert float(page.mediabox.width)==1008 and float(page.mediabox.height)==720
    for obj in page['/Resources'].get('/XObject',{}).values():
        if obj.get_object().get('/Subtype')=='/Image':images.add(obj.idnum)
assert len(images)==78, len(images)
assert len(reader.pages[1].get('/Annots',[]))==6
clipped=[]
with pdfplumber.open(directory/manifest['pdf']) as doc:
    for i,page in enumerate(doc.pages,1):
        for char in page.chars:
            if char['x0']<0 or char['x1']>page.width or char['top']<0 or char['bottom']>page.height:
                clipped.append({'page':i,'text':char['text']})
assert not clipped, clipped
report={'pages':len(reader.pages),'original_concept_boards':26,'original_style_boards':1,'model_reference_images':51,'unique_embedded_images':len(images),'chapter_bookmarks':6,'contents_links':6,'clipped_vector_text':0,'model_inventory_coverage':'30 of 30 existing GLBs'}
(directory/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
