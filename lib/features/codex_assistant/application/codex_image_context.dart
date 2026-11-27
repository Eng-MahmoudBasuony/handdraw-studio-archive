import 'dart:convert';
import 'codex_text_lines.dart';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

final class CodexImageContext {
  const CodexImageContext({
    required this.hash,
    required this.imageUrl,
    required this.texts,
  });
  final String hash, imageUrl;
  final List<SmartTextRegion> texts;

  static Future<CodexImageContext> prepare(ui.Image image) async {
    final original = await image.toByteData(format: ui.ImageByteFormat.png);
    if (original == null) throw StateError('Could not read image');
    final bytes = original.buffer.asUint8List(
      original.offsetInBytes,
      original.lengthInBytes,
    );
    List<SmartTextRegion> texts;
    try {
      texts = await const MethodChannelTextLayoutDetector().detect(bytes);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw != null) {
        texts = const CodexTextLines().resolve(
          texts,
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
          image.width,
          image.height,
        );
      }
    } catch (_) {
      texts = const [];
    }
    final scale =
        1024 / (image.width > image.height ? image.width : image.height);
    final ratio = scale < 1 ? scale : 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(ratio);
    canvas.drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(
      (image.width * ratio).round(),
      (image.height * ratio).round(),
    );
    picture.dispose();
    try {
      final png = (await resized.toByteData(format: ui.ImageByteFormat.png))!;
      return CodexImageContext(
        hash: sha256.convert(bytes).toString(),
        imageUrl:
            'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}',
        texts: List.unmodifiable(texts.take(100)),
      );
    } finally {
      resized.dispose();
    }
  }

  Map<String, dynamic> get textMap => {
    'textLines': [
      for (var i = 0; i < texts.length; i++)
        {
          'id': 'text-$i',
          'text': texts[i].text,
          'bounds': [
            texts[i].bounds.left,
            texts[i].bounds.top,
            texts[i].bounds.right,
            texts[i].bounds.bottom,
          ].map((v) => double.parse(v.toStringAsFixed(4))).toList(),
        },
    ],
  };
}
