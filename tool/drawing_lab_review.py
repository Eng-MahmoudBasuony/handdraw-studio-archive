"""Package existing measured frames; never add a terminal source frame.
Run using the quality-lab venv (Pillow/numpy) after the Flutter visual benchmark.
"""
from pathlib import Path
import json, subprocess
from PIL import Image, ImageDraw, ImageFont
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/drawing_lab_review'
OLD=ROOT.parent/'handdraw_quality_lab_2026-09-05'
FONT=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
metrics=[]
for name,previous,box in [('04-build-fails','build_fails',(320,780,1560,1020)),('00-title','title',(390,60,1530,280))]:
    images=[OLD/previous/'A_current_masks.mp4',OUT/f'{name}-linesFirst.mp4',OUT/f'{name}-regionFirst.mp4']
    labels=['Current masks - no terminal source substitution','Experiment - all lines then paint','Experiment - complete each region']
    x,y,xx,yy=box;w=xx-x;h=yy-y
    filters=[]
    label_image=Image.new("RGBA",(w,(h+32)*3),(0,0,0,0))
    for i,label in enumerate(labels):ImageDraw.Draw(label_image).text((12,i*(h+32)+7),label,font=FONT,fill="black")
    label_file=OUT/f"labels-{name}.png";label_image.save(label_file)
    for i,label in enumerate(labels):
        filters.append(f'[{i}:v]crop={w}:{h}:{x}:{y},pad={w}:{h+32}:0:32:white[v{i}]')
    filters.append('[v0][v1][v2]vstack=inputs=3[stacked];[stacked][3:v]overlay=eof_action=repeat[out]')
    args=['/opt/homebrew/bin/ffmpeg','-y','-loglevel','error']
    for path in images+[label_file]:args+=['-i',str(path)]
    subprocess.run(args+['-filter_complex',';'.join(filters),'-map','[out]','-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(OUT/f'comparison-{name}.mp4')],check=True)
    steps=[36,108,216,288,359]
    cellw=800;cellh=round(h*cellw/w);
    sheet=Image.new('RGB',(cellw*3, (cellh+42)*len(steps)),'white')
    originals=np.array(Image.open(ROOT/f'test/fixtures/{name}.png').convert('RGBA'))
    fg=originals[:,:,3]>0
    for row,(label,variant) in enumerate(zip(labels,[None,'linesFirst','regionFirst'])):
        for col,frame in enumerate(steps):
            if variant is None:
                # Existing A checkpoints follow zero-padded filenames.
                candidate=list((OLD/previous).glob(f'A*{frame:03d}*.png'))
                if not candidate:continue
                path=candidate[0]
            else:path=OUT/f'{name}-{variant}-{frame}.png'
            image=Image.open(path).convert('RGBA')
            white=Image.alpha_composite(Image.new('RGBA',image.size,'white'),image).convert('RGB').crop(box)
            target=col*(cellh+42);left=row*cellw
            sheet.paste(white.resize((cellw,cellh)),(left,target+42));ImageDraw.Draw(sheet).text((left+10,target+10),f'{label} - {frame/30:.2f}s',font=FONT,fill='black')
            if variant:
                a=np.array(image).astype(int);o=originals.astype(int)
                metrics.append({'image':name,'order':variant,'frame':frame,'foreground_alpha_shortfall_gt12_fraction':float(((o[:,:,3]-a[:,:,3]>12)&fg).sum()/fg.sum()),'foreground_RGBA_MAE':float(np.abs(o[fg]-a[fg]).mean())})
    sheet.save(OUT/f'progress-{name}.png')
(OUT/'quality-checkpoints.json').write_text(json.dumps(metrics,indent=2))
# UI capture only: crop/encode the actual recording, not a reconstructed mockup.
if (OUT/'ui-use-final.mov').exists():
    subprocess.run(['/opt/homebrew/bin/ffmpeg','-y','-loglevel','error','-i',str(OUT/'ui-use-final.mov'),'-an','-c:v','libx264','-crf','21','-pix_fmt','yuv420p',str(OUT/'ui-use-final.mp4')],check=True)
