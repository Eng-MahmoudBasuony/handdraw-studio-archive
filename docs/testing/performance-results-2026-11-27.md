# Performance validation — 2026-11-27

All nine opt-in benchmarks were enabled. The complete suite ran serially:
**926 passed, zero failures, zero skips** (154 seconds reported by the test runner).
Flutter analyze reports no issues. All 45 golden-reference SHA-256 hashes remain unchanged.

Environment: Apple M4 Pro, 24 GiB RAM, macOS 27.2.1 arm64, Flutter 3.47.9,
Dart 3.13.7. These are Debug/JIT software-rendering test measurements, not Release
FPS or guarantees about interactive playback on other machines. Most probes
record timings; they do not enforce a product performance budget.

## Corrections discovered during validation

- The legacy baseline and camera benchmark truncated individual durations to
  integer microseconds, printing misleading zero values for fast operations.
  They now retain Stopwatch ticks and convert only when reporting, including
  the clock frequency.
- The camera sequential benchmark sampled only the first shot despite creating
  up to 1,000 shots. Samples now span the entire track. Resolved values feed a
  checksum outside the timed interval, and the compiled track is statically
  typed. This makes the reported workload representative of the stated size.

Only test measurement code changed. No drawing, playback, saving or export
implementation was modified.

## Results from the final full-suite run

| Enabled benchmark | Result | Representative measurement |
|---|---|---|
| Timeline/render/memory baseline | Passed | 1080p/40 paths: mean 19.49 ms, p95 24.86 ms; 4K: mean 78.20 ms; 1080p/600 paths: mean 19.75 ms |
| Playback tick | Passed | 1,000 sections, 20,000 samples: mean 0.893 µs; p95 2.542 µs |
| Image animation stages | Passed | Source planning 210 ms/202 strokes; import 103 ms; integrated analysis/commit 166 ms/95 strokes |
| Global timeline compiler/resolver | Passed | 1,000 sections: compile mean 84.919 µs; warm sequential mean 0.131 µs; random mean 0.129 µs |
| Dense export frame | Passed | 2,190 paths at 1080p: render 39 ms, raw extraction 1 ms, PNG encoding 45 ms |
| Real-image video benchmark | Passed | Four 1080p videos; render+encode took 4.704–11.653 seconds per 12-second video |
| Camera compiler/resolver | Passed | 1,000 shots: compile mean 237.425 µs; random resolve mean 0.216 µs; sequential mean 0.111 µs |
| Large asset staging | Passed | Streamed 500 MiB without reading the entire source into one byte array |
| Camera frame renderer | Passed | 1080p: identity 23.95 ms, move 23.96 ms, fade 51.68 ms; 4K fade 206.79 ms mean |

The camera frame probe has only three samples per case; these figures are
observations, not a statistically established throughput target. Memory samples
showed up to about 1.24 GB RSS after dense/4K rendering in the baseline process.
A short RSS increase alone does not establish a memory leak; no sustained
memory-leak conclusion is made from this probe.

## Encoded artifacts

All four MP4s were independently probed and fully decoded with FFmpeg: 1920×1080,
30 fps, 360 frames, 12.000 seconds each. They are review MP4s composited on white;
this run does not qualify the separate transparent MOV encoding pipeline.

Evidence is under `build/quality-review/2026-11-27/performance/`:

- `full-suite.log`: complete final run including timing and AA diagnostics.
- `summary.json`, `metrics-lines.json`, `analyze.log`.
- `full-videos/metrics.json`: individual frame timings and RSS for each video.
- `video-validation.json`: independently verified stream and decoding results.
- `run.log`: initial nine-file run before measurement corrections (17 tests,
  including eight ordinary staging tests; all passed). Use final-run measurements
  for the corrected baseline.

To reproduce from the repository root on this machine:

```sh
flutter test --concurrency=1 --reporter=expanded --dart-define-from-file=build/quality-review/2026-11-27/performance/dart-defines.json
```

The definitions file includes the source fixture path and enables all nine probes.
