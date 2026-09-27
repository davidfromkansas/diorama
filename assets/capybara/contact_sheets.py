from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
OUT=Path(__file__).resolve().parent
try:font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',22);small=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',16)
except OSError:font=small=ImageFont.load_default()
def sheet(files,name,cols=4,size=300):
    rows=(len(files)+cols-1)//cols;im=Image.new('RGB',(cols*size,rows*(size+35)+60),'#f6f2eb');d=ImageDraw.Draw(im);d.text((20,17),name.replace('_',' ').title(),fill='#554331',font=font)
    for i,f in enumerate(files):
        if not f.exists():continue
        x=i%cols*size;y=i//cols*(size+35)+60
        im.paste(Image.open(f).convert('RGB').resize((size,size)),(x,y));d.text((x+12,y+size+7),f.stem.replace('pose_','').replace('face_','').replace('_',' ').title(),fill='#6b513b',font=small)
    im.save(OUT/'renders'/f'{name}.jpg',quality=94)
sheet([OUT/'renders'/f'{n}.png' for n in ['front','left','back','right','front_three_quarter','rear_three_quarter']],'turnaround',3,380)
sheet(sorted((OUT/'renders').glob('pose_*.png')),'animation_contact_sheet',4,300)
sheet(sorted((OUT/'renders').glob('face_*.png')),'expressions',4,260)
# Compare reference and render at a consistent 239-pixel character height.
ref=Image.open(OUT/'reference_orthographic.png').convert('RGB')
im=Image.new('RGB',(1120,670),'#f6f2eb');draw=ImageDraw.Draw(im)
draw.text((20,15),'Orthographic comparison — updated reference / authored mesh',font=font,fill='#554331')
for i,(name,rect) in enumerate([('front',(60,140,263,384)),('left',(282,140,450,384)),('back',(457,140,652,384)),('right',(659,140,829,384))]):
    crop=ref.crop(rect);crop.thumbnail((250,244));x=i*280+(280-crop.width)//2;im.paste(crop,(x,60))
    r=Image.open(OUT/'renders'/f'{name}.png').convert('RGB')
    # 1.2 m orthographic frame: scale the 1 m figure to the reference's 239 px.
    r=r.resize((287,287));im.paste(r, (i*280-3,340))
    draw.text((i*280+90,315),name.upper(),fill='#6b513b',font=small)
im.save(OUT/'renders'/'reference_comparison.jpg',quality=95)
