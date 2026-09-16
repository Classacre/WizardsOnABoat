"""Make small QA contact sheets from already rendered PDF pages."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

p=argparse.ArgumentParser();p.add_argument('directory');p.add_argument('--pages',default='');args=p.parse_args()
directory=Path(args.directory)
files=sorted(directory.glob('page-*.png'))
if args.pages:
    selected={int(n) for n in args.pages.split(',')}
    files=[f for f in files if int(f.stem.split('-')[-1]) in selected]
font=ImageFont.truetype('C:/Windows/Fonts/calibri.ttf',16)
for start in range(0,len(files),12):
    batch=files[start:start+12]
    sheet=Image.new('RGB',(1260,1280),'#d9e0df');d=ImageDraw.Draw(sheet)
    for i,path in enumerate(batch):
        im=Image.open(path).convert('RGB');im.thumbnail((400,286))
        x=10+(i%3)*420;y=10+(i//3)*320
        sheet.paste(im,(x,y));d.text((x,y+291),path.stem,font=font,fill='#143a46')
    output=directory/f'contact-{start//12+1:02}.jpg'
    sheet.save(output,quality=94);print(output.resolve())
