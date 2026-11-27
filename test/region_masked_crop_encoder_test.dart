import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:image/image.dart' as raster;

import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/region_auto_path_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'isolate crop worker preserves exact source pixels and polygon alpha',
    () async {
      final source = raster.Image(width: 4, height: 4, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(x, y, 20 + x, 40 + y, 60 + x + y, 200 + x);
        }
      }
      final rgba = Uint8List(source.width * source.height * 4);
      var offset = 0;
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final pixel = source.getPixel(x, y);
          rgba[offset++] = pixel.r.toInt();
          rgba[offset++] = pixel.g.toInt();
          rgba[offset++] = pixel.b.toInt();
          rgba[offset++] = pixel.a.toInt();
        }
      }
      final session = await const IsolateRegionMaskedCropEncoder().open(
        rgba: rgba,
        sourceWidth: source.width,
        sourceHeight: source.height,
      );
      addTearDown(session.close);

      final crop = await session.encode(
        SceneRegion(
          id: 'triangle',
          name: 'Triangle',
          polygon: const [ui.Offset(0, 0), ui.Offset(1, 0), ui.Offset(0, 1)],
        ),
      );

      expect(crop, isNotNull);
      expect(crop!.bounds, const ui.Rect.fromLTWH(0, 0, 1, 1));
      final decoded = raster.decodePng(crop.encodedPng)!;
      final retained = decoded.getPixel(0, 0);
      expect(retained.r.toInt(), 20);
      expect(retained.g.toInt(), 40);
      expect(retained.b.toInt(), 60);
      expect(retained.a.toInt(), 200);
      expect(decoded.getPixel(3, 3).a.toInt(), 0);
    },
  );

  test(
    'analyzer keeps a region when Auto Path marks every section ignored',
    () async {
      final encoded = Uint8List.fromList(
        raster.encodePng(
          raster.Image(width: 8, height: 8, numChannels: 4)
            ..clear(raster.ColorRgba8(10, 20, 30, 255)),
        ),
      );
      final codec = await ui.instantiateImageCodec(encoded);
      final frame = await codec.getNextFrame();
      addTearDown(() {
        frame.image.dispose();
        codec.dispose();
      });
      final region = SceneRegion(
        id: 'kept-region',
        name: 'Scene 1',
        polygon: rectPolygon(const ui.Rect.fromLTWH(0, 0, 1, 1)),
      );

      final result = await const RegionAutoPathAnalyzer().analyze(
        source: frame.image,
        regions: [region],
        facade: const _IgnoreOnlyFacade(),
      );

      expect(result, hasLength(1));
      expect(result.single.id, 'kept-region::fallback');
      expect(result.single.label, 'Scene 1');
      expect(result.single.mode, SmartSectionMode.revealText);
      expect(result.single.paths.single.points, hasLength(2));
    },
  );

  test(
    'fragment fast path is deterministic and performs no polygon searches',
    () async {
      const dimension = 256;
      final rgba = Uint8List(dimension * dimension * 4);
      for (var pixel = 0; pixel < dimension * dimension; pixel++) {
        final offset = pixel * 4;
        rgba[offset] = pixel % 251;
        rgba[offset + 1] = (pixel ~/ dimension) % 241;
        rgba[offset + 2] = 173;
        rgba[offset + 3] = 219;
      }
      final fragments = <ui.Rect>[
        for (var y = 0; y < 16; y++)
          for (var x = 0; x < 16; x++)
            if ((x + y).isEven)
              ui.Rect.fromLTWH(x / 16, y / 16, 1 / 32, 1 / 32),
        const ui.Rect.fromLTWH(31 / 32, 31 / 32, 1 / 32, 1 / 32),
      ];
      final region = SceneRegion(
        id: 'many-fragments',
        name: 'Many fragments',
        polygon: rectPolygon(const ui.Rect.fromLTWH(0, 0, 1, 1)),
        fragments: fragments,
        automatic: true,
      );
      final session = await const IsolateRegionMaskedCropEncoder().open(
        rgba: rgba,
        sourceWidth: dimension,
        sourceHeight: dimension,
      );
      addTearDown(session.close);

      final first = (await session.encode(region))!;
      final second = (await session.encode(region))!;

      expect(first.polygonMembershipTests, 0);
      expect(second.polygonMembershipTests, 0);
      expect(second.encodedPng, orderedEquals(first.encodedPng));
      final decoded = raster.decodePng(first.encodedPng)!;
      expect(decoded.getPixel(2, 2).a.toInt(), 219);
      expect(decoded.getPixel(12, 12).a.toInt(), 0);
      expect(decoded.getPixel(253, 253).a.toInt(), 219);
    },
  );

  test('additional polygons are unioned over the fragment fast path', () async {
    const dimension = 32;
    final rgba = Uint8List(dimension * dimension * 4);
    for (var offset = 0; offset < rgba.length; offset += 4) {
      rgba[offset] = 11;
      rgba[offset + 1] = 22;
      rgba[offset + 2] = 33;
      rgba[offset + 3] = 177;
    }
    final session = await const IsolateRegionMaskedCropEncoder().open(
      rgba: rgba,
      sourceWidth: dimension,
      sourceHeight: dimension,
    );
    addTearDown(session.close);
    final crop = (await session.encode(
      SceneRegion(
        id: 'fragment-plus-polygon',
        name: 'Union',
        polygon: rectPolygon(const ui.Rect.fromLTWH(0, 0, 1, 1)),
        fragments: const [ui.Rect.fromLTWH(0, 0, 0.25, 0.25)],
        additionalPolygons: const [
          [ui.Offset(0.5, 0.5), ui.Offset(1, 0.5), ui.Offset(1, 1)],
        ],
        automatic: true,
      ),
    ))!;

    final decoded = raster.decodePng(crop.encodedPng)!;
    expect(decoded.getPixel(2, 2).a.toInt(), 177);
    expect(decoded.getPixel(29, 20).a.toInt(), 177);
    expect(decoded.getPixel(12, 20).a.toInt(), 0);
    expect(crop.polygonMembershipTests, lessThan(dimension * dimension));
  });

  test(
    'fragment fast path matches center-point Rect.contains exactly',
    () async {
      const width = 73;
      const height = 51;
      final rgba = Uint8List(width * height * 4);
      for (var pixel = 0; pixel < width * height; pixel++) {
        final offset = pixel * 4;
        rgba[offset] = pixel % 255;
        rgba[offset + 1] = (pixel * 3) % 255;
        rgba[offset + 2] = (pixel * 7) % 255;
        rgba[offset + 3] = 181;
      }
      final region = SceneRegion(
        id: 'fractional-fragments',
        name: 'Fractional',
        polygon: rectPolygon(const ui.Rect.fromLTWH(0, 0, 1, 1)),
        fragments: const [
          ui.Rect.fromLTWH(0.103, 0.207, 0.318, 0.229),
          ui.Rect.fromLTWH(0.48, 0.04, 0.117, 0.531),
        ],
        automatic: true,
      );
      final session = await const IsolateRegionMaskedCropEncoder().open(
        rgba: rgba,
        sourceWidth: width,
        sourceHeight: height,
      );
      addTearDown(session.close);
      final crop = (await session.encode(region))!;
      final decoded = raster.decodePng(crop.encodedPng)!;
      final cropLeft = (crop.bounds.left * width).round();
      final cropTop = (crop.bounds.top * height).round();

      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final sourceX = cropLeft + x;
          final sourceY = cropTop + y;
          final included = region.contains(
            ui.Offset((sourceX + 0.5) / width, (sourceY + 0.5) / height),
          );
          final actual = decoded.getPixel(x, y);
          expect(
            actual.a.toInt(),
            included ? 181 : 0,
            reason: '$sourceX,$sourceY',
          );
          if (included) {
            final sourceOffset = (sourceY * width + sourceX) * 4;
            expect(actual.r.toInt(), rgba[sourceOffset]);
            expect(actual.g.toInt(), rgba[sourceOffset + 1]);
            expect(actual.b.toInt(), rgba[sourceOffset + 2]);
          }
        }
      }
      expect(crop.polygonMembershipTests, 0);
    },
  );

  test(
    'closing a busy worker completes its pending encode with an error',
    () async {
      const dimension = 1536;
      final session = await const IsolateRegionMaskedCropEncoder().open(
        rgba: Uint8List(dimension * dimension * 4),
        sourceWidth: dimension,
        sourceHeight: dimension,
      );
      final pending = session.encode(
        SceneRegion(
          id: 'cancelled',
          name: 'Cancelled',
          polygon: rectPolygon(const ui.Rect.fromLTWH(0, 0, 1, 1)),
        ),
      );
      final expectation = expectLater(pending, throwsA(isA<StateError>()));

      final firstClose = session.close();
      final repeatedClose = session.close();
      expect(identical(firstClose, repeatedClose), isTrue);
      await Future.wait([firstClose, repeatedClose]);

      await expectation.timeout(const Duration(seconds: 2));
    },
  );
}

final class _IgnoreOnlyFacade implements ArtworkPathFacade {
  const _IgnoreOnlyFacade();

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async =>
      ArtworkPathResult(
        analysis: const SmartPathAnalysis(
          sections: [
            SmartPathSection(
              id: 'ignored',
              kind: SmartSectionKind.shape,
              bounds: ui.Rect.fromLTWH(0, 0, 1, 1),
              label: 'Ignored',
              paths: [],
              recommendedRevealWidth: 0.01,
              mode: SmartSectionMode.ignore,
            ),
          ],
        ),
      );
}
