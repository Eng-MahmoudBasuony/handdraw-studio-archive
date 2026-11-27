# Third-Party Notices

## Inkplainer canvas-background presets

The canvas-background preset vocabulary and initial procedural color/pattern
recipes were adapted from Inkplainer and reimplemented in Dart for HandDraw
Studio's shared preview/export renderer.

- Upstream: <https://github.com/NadirWeb-App/Inkplainer-OS>
- Source file reviewed: `index.html`
- License: Apache License 2.0
- Changes: translated from browser Canvas JavaScript to resolution-independent
  Dart picture rendering, added bounded picture caching, camera composition,
  project persistence, Undo/Redo, localization, and custom-color editing.

Inkplainer is provided under the
[Apache License 2.0](licenses/Apache-2.0.txt).

## Koni archive packages

HandDraw Studio uses the following exact package versions:

- `koni_archive_core 0.9.0`
- `koni_zip 0.9.0`
- `koni_codecs 0.9.0` (transitive)

Upstream: <https://github.com/zenbaku/koni_archive>  
Approved tag: `v0.9.0`  
Approved commit: `e827474de5e7c4e5d309e2c9daa08c96f145d86c`

All three packages use the following MIT license:

```text
MIT License

Copyright (c) 2026 the koni_archive authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
