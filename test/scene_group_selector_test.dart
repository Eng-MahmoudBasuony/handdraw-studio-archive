import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/scene_group_selector.dart';

void main() {
  const selector = SceneGroupSelector();

  test('freehand enclosure selects complete sections, not path fragments', () {
    final sections = [
      _section('left', const Rect.fromLTWH(0.1, 0.2, 0.2, 0.2)),
      _section('right', const Rect.fromLTWH(0.7, 0.2, 0.2, 0.2)),
    ];

    final selected = selector.select(
      enclosure: const [
        Offset(0.05, 0.15),
        Offset(0.38, 0.15),
        Offset(0.38, 0.48),
        Offset(0.05, 0.48),
      ],
      sections: sections,
    );

    expect(selected, ['left']);
  });

  test('canvas-spanning decorations remain outside manual scene groups', () {
    final selected = selector.select(
      enclosure: const [Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      sections: [
        _section(
          'global',
          const Rect.fromLTWH(0.05, 0.1, 0.9, 0.8),
          role: SmartSectionRole.globalDecoration,
        ),
      ],
    );

    expect(selected, isEmpty);
  });
}

SmartPathSection _section(
  String id,
  Rect bounds, {
  SmartSectionRole role = SmartSectionRole.content,
}) => SmartPathSection(
  id: id,
  kind: SmartSectionKind.shape,
  bounds: bounds,
  label: id,
  paths: [
    SmartGeneratedPath(points: [bounds.topLeft, bounds.bottomRight]),
  ],
  recommendedRevealWidth: 0.01,
  mode: SmartSectionMode.handDraw,
  role: role,
);
