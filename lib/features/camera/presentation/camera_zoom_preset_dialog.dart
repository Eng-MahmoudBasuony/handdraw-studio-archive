import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_zoom_in_out_preset_planner.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraZoomPresetSettings {
  const CameraZoomPresetSettings({
    required this.strength,
    required this.zoomInDuration,
    required this.zoomOutDuration,
  });

  final double strength;
  final TimelineDuration zoomInDuration;
  final TimelineDuration zoomOutDuration;
}

class CameraZoomPresetDialog extends StatefulWidget {
  const CameraZoomPresetDialog({super.key, required this.totalDuration});

  final TimelineDuration totalDuration;

  @override
  State<CameraZoomPresetDialog> createState() => _CameraZoomPresetDialogState();
}

class _CameraZoomPresetDialogState extends State<CameraZoomPresetDialog> {
  double strength = 1.6;
  late double zoomInSeconds;
  late double zoomOutSeconds;

  bool get isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
  String text(String english, String arabic) => isArabic ? arabic : english;

  double get totalSeconds =>
      widget.totalDuration.microseconds / Duration.microsecondsPerSecond;
  double get reservedSeconds =>
      (CameraZoomInOutPresetPlanner.edgeHoldDuration.microseconds * 2 +
          CameraZoomInOutPresetPlanner.minimumCloseHoldDuration.microseconds) /
      Duration.microsecondsPerSecond;
  double get minimumMovementSeconds =>
      CameraZoomInOutPresetPlanner.minimumMovementDuration.microseconds /
      Duration.microsecondsPerSecond;
  double get maximumSingleDuration => math.max(
    minimumMovementSeconds,
    math.min(3, totalSeconds - reservedSeconds - minimumMovementSeconds),
  );
  bool get isValid =>
      zoomInSeconds + zoomOutSeconds + reservedSeconds <= totalSeconds + 1e-6;
  double get holdSeconds => math.max(
    0,
    totalSeconds - reservedSeconds - zoomInSeconds - zoomOutSeconds,
  );

  @override
  void initState() {
    super.initState();
    final available = math.max(
      minimumMovementSeconds * 2,
      totalSeconds - reservedSeconds,
    );
    zoomInSeconds = math.min(.8, available / 2);
    zoomOutSeconds = math.min(.8, available / 2);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('camera-zoom-preset-dialog'),
    title: Text(text('Zoom In then Out', 'تقريب ثم إبعاد')),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text(
              'Uses the current frame center as the focus, then returns to the full scene.',
              'يستخدم مركز الكادر الحالي كنقطة تركيز، ثم يرجع للمشهد كاملًا.',
            ),
          ),
          const SizedBox(height: 18),
          _PresetSlider(
            key: const ValueKey('camera-zoom-preset-strength'),
            label: text('Zoom strength', 'قوة التقريب'),
            valueLabel: '${strength.toStringAsFixed(1)}×',
            value: strength,
            minimum: 1.2,
            maximum: 4,
            divisions: 28,
            onChanged: (value) => setState(() => strength = value),
          ),
          _PresetSlider(
            key: const ValueKey('camera-zoom-preset-in-duration'),
            label: text('Zoom in', 'مدة التقريب'),
            valueLabel: '${zoomInSeconds.toStringAsFixed(1)}s',
            value: zoomInSeconds.clamp(
              minimumMovementSeconds,
              maximumSingleDuration,
            ),
            minimum: minimumMovementSeconds,
            maximum: maximumSingleDuration,
            divisions: math.max(
              1,
              ((maximumSingleDuration - minimumMovementSeconds) * 10).round(),
            ),
            onChanged: (value) => setState(() => zoomInSeconds = value),
          ),
          _PresetSlider(
            key: const ValueKey('camera-zoom-preset-out-duration'),
            label: text('Zoom out', 'مدة الإبعاد'),
            valueLabel: '${zoomOutSeconds.toStringAsFixed(1)}s',
            value: zoomOutSeconds.clamp(
              minimumMovementSeconds,
              maximumSingleDuration,
            ),
            minimum: minimumMovementSeconds,
            maximum: maximumSingleDuration,
            divisions: math.max(
              1,
              ((maximumSingleDuration - minimumMovementSeconds) * 10).round(),
            ),
            onChanged: (value) => setState(() => zoomOutSeconds = value),
          ),
          const SizedBox(height: 8),
          Text(
            isValid
                ? text(
                    'The close view holds for ${holdSeconds.toStringAsFixed(1)}s.',
                    'يثبت الكادر القريب لمدة ${holdSeconds.toStringAsFixed(1)} ث.',
                  )
                : text(
                    'The movement durations are longer than this camera shot.',
                    'مدتا الحركة أطول من مدة لقطة الكاميرا.',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isValid
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(text('Cancel', 'إلغاء')),
      ),
      FilledButton(
        key: const ValueKey('camera-zoom-preset-apply'),
        onPressed: isValid
            ? () => Navigator.of(context).pop(
                CameraZoomPresetSettings(
                  strength: strength,
                  zoomInDuration: TimelineDuration.fromMicroseconds(
                    (zoomInSeconds * Duration.microsecondsPerSecond).round(),
                  ),
                  zoomOutDuration: TimelineDuration.fromMicroseconds(
                    (zoomOutSeconds * Duration.microsecondsPerSecond).round(),
                  ),
                ),
              )
            : null,
        child: Text(text('Create 3 shots', 'إنشاء 3 لقطات')),
      ),
    ],
  );
}

class _PresetSlider extends StatelessWidget {
  const _PresetSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(valueLabel),
        ],
      ),
      Slider(
        value: value,
        min: minimum,
        max: maximum,
        divisions: divisions,
        label: valueLabel,
        onChanged: onChanged,
      ),
    ],
  );
}
