import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class HandCalibrationDialog extends StatefulWidget {
  const HandCalibrationDialog({
    super.key,
    required this.image,
    required this.initialPenTip,
    this.flipX = false,
  });

  final ui.Image image;
  final Offset initialPenTip;
  final bool flipX;

  @override
  State<HandCalibrationDialog> createState() => _HandCalibrationDialogState();
}

class _HandCalibrationDialogState extends State<HandCalibrationDialog> {
  late Offset penTip = widget.flipX
      ? Offset(1 - widget.initialPenTip.dx, widget.initialPenTip.dy)
      : widget.initialPenTip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.clickExactPenTip),
      content: SizedBox(
        width: 620,
        height: 440,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final imageRect = _fitRect(widget.image, size);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                if (!imageRect.contains(details.localPosition)) return;
                setState(() {
                  penTip = Offset(
                    (details.localPosition.dx - imageRect.left) /
                        imageRect.width,
                    (details.localPosition.dy - imageRect.top) /
                        imageRect.height,
                  );
                });
              },
              child: CustomPaint(
                painter: _HandCalibrationPainter(
                  image: widget.image,
                  imageRect: imageRect,
                  penTip: penTip,
                  flipX: widget.flipX,
                  colors: context.studioColors,
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.flipX ? Offset(1 - penTip.dx, penTip.dy) : penTip,
          ),
          child: Text(l10n.useThisPoint),
        ),
      ],
    );
  }
}

Rect _fitRect(ui.Image image, Size size) {
  final imageRatio = image.width / image.height;
  final viewRatio = size.width / size.height;
  if (imageRatio > viewRatio) {
    final height = size.width / imageRatio;
    return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
  }
  final width = size.height * imageRatio;
  return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
}

class _HandCalibrationPainter extends CustomPainter {
  _HandCalibrationPainter({
    required this.image,
    required this.imageRect,
    required this.penTip,
    required this.flipX,
    required this.colors,
  });

  final ui.Image image;
  final Rect imageRect;
  final Offset penTip;
  final bool flipX;
  final StudioThemeColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.workspace);
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.save();
    if (flipX) {
      canvas.translate(imageRect.left + imageRect.right, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        image,
        source,
        imageRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawImageRect(
        image,
        source,
        imageRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    canvas.restore();
    final target = Offset(
      imageRect.left + penTip.dx * imageRect.width,
      imageRect.top + penTip.dy * imageRect.height,
    );
    final paint = Paint()
      ..color = colors.danger
      ..strokeWidth = 2;
    canvas.drawCircle(target, 8, Paint()..color = colors.scrim);
    canvas.drawCircle(target, 7, paint..style = PaintingStyle.stroke);
    canvas.drawLine(
      target - const Offset(13, 0),
      target + const Offset(13, 0),
      paint,
    );
    canvas.drawLine(
      target - const Offset(0, 13),
      target + const Offset(0, 13),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HandCalibrationPainter oldDelegate) =>
      oldDelegate.penTip != penTip ||
      oldDelegate.image != image ||
      oldDelegate.flipX != flipX ||
      oldDelegate.colors != colors;
}
