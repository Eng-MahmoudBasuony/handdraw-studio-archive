# Controlled golden comparison

Flutter 3.47.9 is the validated CI toolchain. Test references were captured
across earlier framework versions. Running 3.44.4, 3.44.9 and 3.47.9 independently
showed different coverage of rounded borders and glyph edges; none matched the
whole collection exactly. Production rendering and reference PNGs are unchanged.

`test/flutter_test_config.dart` installs the test-only
`EdgeAwareGoldenComparator`. This is not a percentage-only or blurred-image
comparison. It never aligns, resizes, filters or modifies either image.

## Acceptance rules

Every changed pixel must satisfy all applicable checks:

- Dimensions and buffer sizes must match. Transparency stays exact; only opaque
  pixels can receive edge tolerance.
- There must be contrast of at least 16 luminance levels in the same 3×3
  neighborhood in both renders. Flat-region differences fail.
- Shared, unchanged colors at identical coordinates within eight pixels must
  provide contrasting anchors. This window reaches the straight portions of
  rounded corners without allowing image translation.
- An isolated modification inside a uniform 2×2 patch fails, including directly
  beside an edge. Extension into such a patch requires an adjacent changed
  transition pixel. The check runs symmetrically on both images.
- Each RGB channel may differ by at most 40/255. Differences up to 3/255 receive
  rounding tolerance only after the spatial and shared-anchor checks.
- Larger changes must follow a color direction between unchanged anchor colors,
  with at most 3/255 channel residual, and remain bracketed by their luminance.
  A luminance-only match cannot excuse a new hue on a grayscale edge.
- Total changed pixels cannot exceed 0.1%. This is a secondary rejection ceiling,
  never a substitute for the per-pixel checks.

Accepted non-exact matches print their image name and edge-pixel count in test
logs. Rejections delegate to Flutter's standard comparator, preserving its
failure images and exact pixel-difference report. Reference updates retain the
standard explicit Flutter workflow; no update command was used for this change.

## Guard tests and limitations

`golden_edge_policy_test.dart` covers 18 cases, including bidirectional rejection
of one-pixel movement, resizing, tiny-element removal, flat-fill changes, RGB hue
changes, transparency changes, blur, dimensions, excessive coverage drift and
widespread differences. Small negative fixtures stay below the area budget, so
the tests exercise local rejection rather than merely exceeding that budget.
`golden_comparator_io_test.dart` exercises real PNG decoding, the installed test
hook, preservation of reference bytes and standard failure-artifact output.

This is a bounded visual test, not a proof of semantic equivalence. An intentional
change confined to a few edge pixels that is numerically identical to allowed
coverage drift is indistinguishable from rasterization noise. Structural widget,
geometry, interaction and rendering tests remain necessary and are still run.
Do not raise thresholds to accommodate a new failure without investigating it.

## Commands

Run the normal suite and static analysis:

```sh
flutter test
flutter analyze
```

The original exact comparator remains available for diagnosis:

```sh
flutter test --dart-define=HANDDRAW_STRICT_GOLDENS=true test/camera_timeline_golden_test.dart
```

On the investigated host, this strict command is expected to reproduce the
original edge differences. It does not update references.

## Validation, 2026-11-27

- Main suite: 917 passed, 9 existing opt-in performance tests skipped, 0 failures.
- Project-container suite: 35 passed, 3 Windows-only cases skipped.
- Development-bridge tests: 6 passed.
- Flutter analyze: no issues.
- SHA-256 checks: all 45 reference PNGs unchanged.
- Evidence: `build/quality-review/2026-11-27/controlled-aa/`.

Follow-up: all nine performance probes were explicitly enabled in a serial full-suite run: **926 passed, zero failures, zero skips**. See `performance-results-2026-11-27.md` for measurements and methodology.
