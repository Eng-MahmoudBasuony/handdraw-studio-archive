import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/drawing_timeline_service.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  const service = DrawingTimelineService();

  test('resolves a saved order and appends newly detected sections', () {
    expect(
      service.resolveOrder(
        availableSectionIds: const ['a', 'b', 'c'],
        preferredOrder: const ['c', 'missing', 'a'],
      ),
      const ['c', 'a', 'b'],
    );
  });

  test('moving a scene moves all of its sections atomically', () {
    final groups = [
      DrawingSceneGroup(
        id: 'scene-1',
        name: 'Scene 1',
        sectionIds: const ['b', 'c'],
      ),
    ];
    final moved = service.reorderNode(
      order: const ['a', 'b', 'c', 'd'],
      groups: groups,
      draggedKey: 'scene:scene-1',
      targetKey: 'section:a',
    );

    expect(moved, const ['b', 'c', 'a', 'd']);
  });

  test('scene members can be reordered without breaking the scene block', () {
    final scene = DrawingSceneGroup(
      id: 'scene-1',
      name: 'Scene 1',
      sectionIds: const ['b', 'c', 'd'],
    );
    final moved = service.reorderSceneMember(
      order: const ['a', 'b', 'c', 'd', 'e'],
      scene: scene,
      draggedSectionId: 'd',
      targetSectionId: 'b',
    );

    expect(moved, const ['a', 'd', 'b', 'c', 'e']);
  });

  test('selected nodes move as one ordered block into an insertion slot', () {
    final moved = service.reorderNodes(
      order: const ['a', 'b', 'c', 'd', 'e'],
      groups: const [],
      draggedKeys: const ['section:b', 'section:d'],
      insertionIndex: 5,
    );

    expect(moved, ['a', 'c', 'e', 'b', 'd']);
  });

  test('batch movement keeps scenes atomic and preserves selected order', () {
    final scene = DrawingSceneGroup(
      id: 'scene-1',
      name: 'Scene 1',
      sectionIds: ['b', 'c'],
    );
    final moved = service.reorderNodes(
      order: const ['a', 'b', 'c', 'd', 'e'],
      groups: [scene],
      draggedKeys: const ['scene:scene-1', 'section:e'],
      insertionIndex: 0,
    );

    expect(moved, ['b', 'c', 'e', 'a', 'd']);
  });

  test('creating a scene makes disjoint selections contiguous', () {
    final created = service.createGroup(
      order: const ['a', 'b', 'c', 'd'],
      selectedSectionIds: const ['a', 'c'],
      id: 'scene-1',
      name: 'Scene 1',
    );

    expect(created.order, const ['a', 'c', 'b', 'd']);
    expect(created.group.sectionIds, const ['a', 'c']);
  });

  test('estimates pre-Apply clip times from drawable path length', () {
    final ranges = service.resolveRanges(
      project: HandDrawProject(durationSeconds: 9),
      order: const ['short', 'long'],
      smartSections: const [
        SmartPathSection(
          id: 'short',
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(0, 0, 0.2, 0.2),
          label: 'Short',
          paths: [
            SmartGeneratedPath(points: [Offset.zero, Offset(0.1, 0)]),
          ],
          recommendedRevealWidth: 0.01,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'long',
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(0.2, 0, 0.8, 0.2),
          label: 'Long',
          paths: [
            SmartGeneratedPath(points: [Offset.zero, Offset(0.8, 0)]),
          ],
          recommendedRevealWidth: 0.01,
          mode: SmartSectionMode.handDraw,
        ),
      ],
    );

    expect(ranges, hasLength(2));
    expect(ranges.first.startSeconds, 0);
    expect(ranges.last.endSeconds, closeTo(9, 0.0001));
    expect(
      ranges.last.durationSeconds,
      greaterThan(ranges.first.durationSeconds),
    );
    expect(ranges.every((range) => range.isEstimate), isTrue);
  });
}
