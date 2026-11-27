# Native Release measurements — 2026-11-27

Apple M4 Pro, 24 GiB RAM, macOS arm64, Flutter 3.47.9, Metal Impeller.
Production EditorScreen and native AVFoundation ProRes 4444 export; 6-second,
30 fps, 180-frame transparent movies at full resolution. No AI calls.

| Workload | Serial export | Bounded pipeline | Reduction |
|---|---:|---:|---:|
| Realistic, 1080p | 2.190 s | 2.037 s | 7.0% |
| Realistic, 4K | 6.560 s | 5.081 s | 22.5% |
| 2,190 paths, 1080p | 1.583 s | 1.387 s | 12.4% |
| 2,190 paths, 4K | 6.555 s | 5.240 s | 20.1% |

One pending native append overlaps preparation of the next frame. Frame order,
rendering settings and pixel data are preserved. All 180 decoded frames in each
before/after pair matched exactly, including alpha; all three raw RGBA captures
per case also matched. All eight MOVs decoded successfully as ProRes 4444 with
alpha, at their stated dimensions and 30 fps.

Real preview warm-playback p95 build times were approximately 2.7 ms for the
realistic workload and 4.2 ms for the dense workload; raster p95 was 2.1–2.4 ms.
These are stage durations, not end-to-end latency or guaranteed FPS. The native
window was 2880×1722 physical pixels; canvas approximately 1589×892 pixels.
A 4K project in this window is not a physically 4K preview. Each case had first
playback and warm replay. Initial frame boundary selection used timestamps;
subsequent instrumentation uses exact engine frame numbers.

These are single before/after export observations, not a statistical performance
promise. Frame readback remains the largest export cost. No preview rendering
optimization was justified by these measurements. The pipeline holds at most
one pending native append plus the frame being prepared; native codec buffers
are additional. Stage timing totals overlap and must not be summed as wall time.

Validation after the change: 936 tests passed with all nine opt-in performance
probes enabled, zero failures/skips. All 45 golden references retained their hashes.
The standalone measurement entry is `tool/release_performance_app.dart` and
requires a Release build and an explicit local `PERF_SOURCE` PNG path.
