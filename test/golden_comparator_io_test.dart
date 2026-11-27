import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/edge_aware_golden_comparator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real PNG comparison preserves references and reports true failures',
    () async {
      if (!const bool.fromEnvironment('HANDDRAW_STRICT_GOLDENS')) {
        expect(goldenFileComparator, isA<EdgeAwareGoldenComparator>());
      }
      final folder = await Directory.systemTemp.createTemp('handdraw-golden-');
      addTearDown(() => folder.delete(recursive: true));
      final pixels = Uint8List(256 * 256 * 4);
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          final i = (y * 256 + x) * 4;
          final shade = x < 128
              ? 0
              : x == 128
              ? 128
              : 255;
          pixels[i] = pixels[i + 1] = pixels[i + 2] = shade;
          pixels[i + 3] = 255;
        }
      }
      Uint8List png(Uint8List rgba) => Uint8List.fromList(
        img.encodePng(
          img.Image.fromBytes(
            width: 256,
            height: 256,
            bytes: rgba.buffer,
            numChannels: 4,
          ),
        ),
      );
      final original = png(pixels);
      final reference = File('${folder.path}/edge.png');
      await reference.writeAsBytes(original);
      final comparator = EdgeAwareGoldenComparator(
        File('${folder.path}/example_test.dart').uri,
      );
      final key = Uri.parse('edge.png');
      expect(await comparator.compare(original, key), isTrue);

      final coverage = Uint8List.fromList(pixels);
      final edge = (40 * 256 + 128) * 4;
      coverage[edge] = coverage[edge + 1] = coverage[edge + 2] = 145;
      expect(await comparator.compare(png(coverage), key), isTrue);

      final changedFill = Uint8List.fromList(pixels);
      changedFill[(40 * 256 + 180) * 4] = 254;
      await expectLater(
        comparator.compare(png(changedFill), key),
        throwsA(isA<FlutterError>()),
      );
      expect(
        File('${folder.path}/failures/edge_testImage.png').existsSync(),
        isTrue,
      );
      expect(
        File('${folder.path}/failures/edge_isolatedDiff.png').existsSync(),
        isTrue,
      );
      expect(await reference.readAsBytes(), orderedEquals(original));
    },
  );
}
