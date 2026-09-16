"""Validate and package the complete-subject model reference collection."""
import hashlib
import json
import zipfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REFS = ROOT / 'preproduction/model-references'
manifest = json.loads((REFS/'generation-manifest.json').read_text(encoding='utf-8-sig'))
wizard = json.loads((ROOT/'preproduction/tripo/input-prompts.json').read_text(encoding='utf-8-sig'))['wizard']
jobs = [{'id':'wizard','title':'The seafaring wizard','category':'Characters','board':'01-wizard.png','prompt':wizard['prompt'],'status':'generated'}]
jobs += [j for j in manifest['jobs'] if j['status'] != 'consolidated']
assert len(jobs) == 51, len(jobs)
assert len({j['id'] for j in jobs}) == len(jobs)
records = []
for job in jobs:
    assert job['status'] == 'generated', (job['id'],job['status'])
    path = REFS / (job['id']+'.png')
    with Image.open(path) as im:
        assert im.format == 'PNG'
        dimensions = list(im.size)
        im.verify()
    records.append({k:job[k] for k in ['id','title','category','board','prompt']} | {
        'image':path.name,'dimensions':dimensions,'edit_prompts':job.get('edit_prompts',[]),
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
index = {'generated_with':'built-in image_gen','subject_policy':'One complete subject in one view. Component segmentation happens in Tripo, not in this image collection.','references':records}
(REFS/'prompts.json').write_text(json.dumps(index,indent=2),encoding='utf-8')

replacement_path = ROOT/'preproduction/tripo/replacement-manifest.json'
replacement = json.loads(replacement_path.read_text(encoding='utf-8-sig'))
for asset in replacement['assets']:
    group = asset['generation_group']
    if group == 'boat_sail':
        group = 'boat'
        asset['generation_group'] = group
        asset['segmentation_note'] = 'Extract the sail from the complete boat using Tripo segmentation.'
    asset['input'] = 'preproduction/model-references/'+group+'.png'
    assert (ROOT/asset['input']).exists(), asset
    asset['status'] = 'reference_ready_not_generated'
    if group == 'glider':
        asset['rig_requirements'] = 'body, two gripping legs, four wings and split tail articulation; follow the approved Threadwing sheet'
    if group == 'hearthstone':
        asset['rig_requirements'] = 'rigid root; rounded carved stone'
replacement['route'] = 'Prepared image references; Tripo generation deferred at user request'
replacement['input_policy'] = 'One complete subject, one view per generation. Use Tripo for segmentation.'
replacement['unique_generation_groups'] = len({a['generation_group'] for a in replacement['assets']})
models = {str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'assets/models').rglob('*.glb')}
assert models == {a['path'] for a in replacement['assets']}, 'Model inventory changed; check coverage.'
replacement_path.write_text(json.dumps(replacement,indent=2),encoding='utf-8')
coverage = [{'model':a['path'],'reference':Path(a['input']).name,'generation_group':a['generation_group'],'rig_requirements':a['rig_requirements']} for a in replacement['assets']]
(REFS/'model-coverage.json').write_text(json.dumps({'existing_models_covered':len(models),'models':coverage},indent=2),encoding='utf-8')
lines = ['# Wizards on a Boat - model reference collection','','51 complete-subject, single-view PNG images derived from the approved visual direction. Created with the built-in image_gen tool.','','## Use','','Open index.html to browse and filter the collection, then use the individual PNG for the subject you want to generate. Submit one PNG per model. Tripo can segment the generated complete object into parts; separate exploded-part images are not needed.','','These are image references, not generated meshes or rigged assets. Rigging, animation and Godot import validation remain future production work.','','prompts.json preserves the exact prompts, original-board names, dimensions and image checksums. model-coverage.json maps all 30 existing GLBs to their replacement reference. Wizard colour and pose variants share wizard.png; boat_sail.glb is covered by the complete boat.png.','','## Subjects','', '| Image | Subject | Category |','| --- | --- | --- |']
lines += [f"| [{r['image']}]({r['image']}) | {r['title']} | {r['category']} |" for r in records]
(REFS/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
out = ROOT/'output/art'
out.mkdir(parents=True,exist_ok=True)
archive = out/'Wizards-on-a-Boat-Model-Reference-Pack.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_STORED) as z:
    for name in [r['image'] for r in records]+['index.html','README.md','prompts.json','model-coverage.json']:
        z.write(REFS/name,'Wizards-on-a-Boat-Model-References/'+name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == 55
print(json.dumps({'archive':str(archive),'images':len(records),'models_covered':len(models),'bytes':archive.stat().st_size}))
