"""Compare two extended path benchmarks; keep raw samples and visual evidence."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import shutil
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('experiment', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
a, b = [json.loads(p.read_text()) for p in (args.baseline, args.experiment)]
assert not a.get('sparseThinning', False) and b['sparseThinning']
assert a['cases'].keys() == b['cases'].keys()
args.output.mkdir(parents=True, exist_ok=True)
rows = []
checks = []
for name, first in a['cases'].items():
    second = b['cases'][name]
    assert first['geometrySignature'] == second['geometrySignature'], name
    assert first['runtime']['frameSha256'] == second['runtime']['frameSha256'], name
    assert first['runtime']['sourceRgbaSha256'] == second['runtime']['sourceRgbaSha256'], name
    assert first['runtime']['previewExportDifferingBytes'] == second['runtime']['previewExportDifferingBytes'] == 0, name
    ma, mb = [statistics.median(x['analysisWarmSamplesUs']) / 1000 for x in (first, second)]
    memory = [max(x['analysisSampledProcessRssBytes']) / 1048576 for x in (first, second)]
    resolve = [statistics.median(x['runtime']['timelineResolveSamplesUs']) / 1000 for x in (first, second)]
    render = [statistics.median(x['runtime']['offlineFrameRenderSamplesUs']) / 1000 for x in (first, second)]
    rows.append(f'| {name} | {ma:.2f} / {mb:.2f} | {(ma-mb)/ma*100:+.1f}% | {memory[0]:.1f} / {memory[1]:.1f} | {resolve[0]:.3f} / {resolve[1]:.3f} | {render[0]:.2f} / {render[1]:.2f} |')
    checks.append({'case':name, 'geometryEqual':True, 'sampledFramesEqual':True, 'previewExportEqual':True})
    for variant, path in [('A', args.baseline), ('B', args.experiment)]:
        target = args.output / variant
        target.mkdir(exist_ok=True)
        for progress in [25, 50, 99, 100]:
            shutil.copy2(path.parent / 'runtime_frames' / f'{name}_{progress}.png', target)
    shutil.copy2(args.baseline.parent / 'path_benchmark_comparisons' / f'{name}_source.png', args.output)
for variant, report in [('A',a),('B',b)]:
    for case in report['cases'].values():
        case['geometrySha256'] = hashlib.sha256(case.pop('geometrySignature').encode()).hexdigest()
    (args.output / f'{variant}.json').write_text(json.dumps(report, indent=2)+'\n')
(args.output / 'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
(args.output / 'measurements.md').write_text('Measured in flutter-test JIT, five post-first analysis samples per case. A / B. Positive reduction means faster analysis. RSS is maximum sampled whole-process resident memory, not attributable allocation or a true peak. Render is eight offline raster samples; it excludes readback, PNG and MOV encoding. No interactive FPS claim.\n\n| Image | Analysis median ms A / B | Reduction | Sampled RSS MiB A / B | Timeline median ms A / B | Offline render median ms A / B |\n|---|---:|---:|---:|---:|---:|\n'+'\n'.join(rows)+'\n')
sections = []
for name in a['cases']:
    n=html.escape(name)
    sections.append(f'<section><h2>{n}</h2><div class="grid"><figure><figcaption>Source</figcaption><img src="{n}_source.png"></figure><figure><figcaption>A · current</figcaption><img data-prefix="A/{n}" src="A/{n}_50.png"></figure><figure><figcaption>B · experiment</figcaption><img data-prefix="B/{n}" src="B/{n}_50.png"></figure></div></section>')
(args.output / 'comparison.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>HandDraw A/B evidence</title><style>body{font:16px system-ui;background:#f5f5f7;color:#18212b;margin:28px}header{position:sticky;top:0;background:#f5f5f7;padding:12px;z-index:1}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}figure{margin:0}img{width:100%;background-color:white;background-image:conic-gradient(#ddd 25%,transparent 0 50%,#ddd 0 75%,transparent 0);background-size:20px 20px}figcaption{padding:8px}button{padding:8px 16px;margin:4px}h2{font-size:18px}section{margin-bottom:30px}</style><header><h1>Same image, same plan, same sampled pixels</h1><p>A: current · B: experimental boundary thinning. Original resolution. No hand, OCR, camera or native MOV encoder in this fixture run.</p><p>View progress: <button onclick="show(25)">25%</button><button onclick="show(50)">50%</button><button onclick="show(99)">99%</button><button onclick="show(100)">100%</button> <strong id="progress">50%</strong></p><a href="measurements.md">Measured timings and memory</a></header>'''+''.join(sections)+'''<script>function show(p){document.querySelectorAll('[data-prefix]').forEach(i=>i.src=i.dataset.prefix+'_'+p+'.png');document.querySelector('#progress').textContent=p+'%';}</script></html>''')
print(args.output / 'comparison.html')
print('\n'.join(rows))
