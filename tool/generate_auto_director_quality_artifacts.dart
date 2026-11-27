import 'dart:convert';
import 'dart:io';

import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  final output = Directory('build/auto_director_quality')
    ..createSync(recursive: true);
  for (final fixture in _fixtures()) {
    final plan = const SmartAutoDirector().generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: fixture.camera,
    );
    final directory = Directory('${output.path}/${fixture.name}')
      ..createSync(recursive: true);
    File('${directory.path}/plan.json').writeAsStringSync('${_json(plan)}\n');
    File(
      '${directory.path}/contact_sheet.svg',
    ).writeAsStringSync(_svg(fixture, plan));
    stdout.writeln('${fixture.name}: ${directory.absolute.path}');
  }
  final shared = _fixture('preset_gallery_source', [
    _s('opening', 0, .45, .38, text: true),
    _s('detail-a', 1200000, .50, .42),
    _s('detail-b', 2400000, .55, .46),
    _s('summary', 3600000, .48, .52, text: true),
  ]);
  final gallery = Directory('${output.path}/preset_gallery')
    ..createSync(recursive: true);
  for (final presetId in AutoDirectorPresetCatalog.presets.keys) {
    final plan = const SmartAutoDirector().generate(
      timeline: shared.timeline,
      graph: shared.graph,
      cameraTrack: shared.camera,
      configuration: const AutoDirectorPresetMapper().configuration(
        ProjectAutoDirectorSettings(presetId: presetId),
      ),
    );
    final directory = Directory('${gallery.path}/${presetId.name}')
      ..createSync(recursive: true);
    File('${directory.path}/plan.json').writeAsStringSync('${_json(plan)}\n');
    File(
      '${directory.path}/contact_sheet.svg',
    ).writeAsStringSync(_svg(shared, plan));
    _writePreviewMov(directory, plan);
    stdout.writeln('preset ${presetId.name}: ${directory.absolute.path}');
  }
}

void _writePreviewMov(Directory directory, AutoDirectorPlan plan) {
  if (plan.proposedShots.isEmpty) return;
  final segments = <File>[];
  for (var index = 0; index < plan.proposedShots.length; index++) {
    final view = plan.proposedShots[index].keyframes.last.view;
    final width = (view.viewportWidth * 640).clamp(24, 640).round();
    final height = (width * 9 / 16).clamp(14, 360).round();
    final x = (view.centerX * 640 - width / 2).clamp(0, 640 - width).round();
    final y = (view.centerY * 360 - height / 2).clamp(0, 360 - height).round();
    final segment = File('${directory.path}/.segment-$index.mov');
    final result = Process.runSync('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=0x101820:s=640x360:d=0.65:r=24',
      '-vf',
      'drawbox=x=$x:y=$y:w=$width:h=$height:color=0x35d0ba:t=4',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      segment.path,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('MOV segment failed: ${result.stderr}');
      return;
    }
    segments.add(segment);
  }
  final concat = File('${directory.path}/.segments.txt')
    ..writeAsStringSync(
      segments.map((file) => "file '${file.absolute.path}'").join('\n'),
    );
  final result = Process.runSync('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    concat.path,
    '-c',
    'copy',
    '${directory.path}/preview.mov',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('MOV concat failed: ${result.stderr}');
  }
  concat.deleteSync();
  for (final segment in segments) {
    segment.deleteSync();
  }
}

typedef _Source = ({
  String id,
  int us,
  double x,
  double y,
  bool text,
  KnownTextDirection direction,
});
typedef _Fixture = ({
  String name,
  CompiledTimeline timeline,
  CompiledSemanticRegionGraph graph,
  ProjectCameraTrack? camera,
});
_Source _s(
  String id,
  int us,
  double x,
  double y, {
  bool text = false,
  KnownTextDirection direction = KnownTextDirection.unknown,
}) => (id: id, us: us, x: x, y: y, text: text, direction: direction);

List<_Fixture> _fixtures() => [
  _fixture('educational_rtl', [
    _s('عنوان', 0, .5, .1, text: true, direction: KnownTextDirection.rtl),
    _s(
      'شرح يمين',
      1000000,
      .8,
      .4,
      text: true,
      direction: KnownTextDirection.rtl,
    ),
    _s('رسم يسار', 2200000, .2, .45),
    _s('ملخص', 3500000, .5, .85, text: true, direction: KnownTextDirection.rtl),
  ]),
  _fixture('ltr_code_explanation', [
    _s('heading', 0, .5, .1, text: true, direction: KnownTextDirection.ltr),
    _s(
      'code left',
      1000000,
      .2,
      .45,
      text: true,
      direction: KnownTextDirection.ltr,
    ),
    _s('diagram right', 2200000, .8, .45),
    _s(
      'summary',
      3500000,
      .5,
      .85,
      text: true,
      direction: KnownTextDirection.ltr,
    ),
  ]),
  _fixture('distant_islands', [
    _s('left island', 0, .07, .5),
    _s('right island', 1400000, .93, .5),
  ]),
  _fixture('text_readability_conflict', [
    _s('small sensitive text', 0, .1, .15, text: true),
    _s('far diagram', 300000, .9, .8),
  ]),
  _fixture(
    'hand_occlusion',
    [_s('edge text', 0, .86, .5, text: true)],
    hand: const HandFootprintDescriptor(
      provenance: HandFootprintProvenance.configuredAsset,
      screenScale: .3,
      penTipX: .95,
      penTipY: .5,
    ),
  ),
  _fixture(
    'manual_locked_coexistence',
    [
      _s('auto before', 0, .2, .3),
      _s('manual target', 1000000, .5, .3),
      _s('auto after', 2000000, .8, .3),
    ],
    camera: ProjectCameraTrack(
      id: CameraTrackId('track'),
      shots: [
        _protected('manual', 1000000, CameraAuthorship.manual),
        _protected('locked-auto', 3000000, CameraAuthorship.auto, locked: true),
      ],
    ),
  ),
];

_Fixture _fixture(
  String name,
  List<_Source> source, {
  HandFootprintDescriptor hand = const HandFootprintDescriptor(
    provenance: HandFootprintProvenance.unknown,
  ),
  ProjectCameraTrack? camera,
}) {
  final durationUs = source.last.us + 1000000;
  final regions = <SemanticRegion>[];
  final events = <SemanticAttentionEvent>[];
  for (final item in source) {
    final target = SemanticTargetReference.stroke(StrokeId(item.id));
    final bounds = SemanticWorldBounds(
      item.x * 1000 - 35,
      item.y * 562.5 - 25,
      item.x * 1000 + 35,
      item.y * 562.5 + 25,
    );
    final metadata = item.text
        ? EntitySemanticMetadata(
            target: target,
            textSensitive: true,
            minimumPreferredZoom: PreferredSemanticZoom(1.5),
            textMetadata: ImportedTextMetadata(
              originalText: item.id,
              direction: item.direction,
              directionProvenance: DirectionProvenance.sourceMetadata,
              sourceKind: TextSourceKind.svgText,
              sourceProvenance: 'quality-fixture',
            ),
          )
        : null;
    regions.add(
      SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: item.text ? SemanticRegionKind.text : SemanticRegionKind.vector,
        geometricBounds: bounds,
        visualBounds: bounds,
        direction: item.direction,
        directionProvenance: item.text
            ? DirectionProvenance.sourceMetadata
            : DirectionProvenance.unknown,
        metadata: metadata,
      ),
    );
    events.add(
      SemanticAttentionEvent(
        time: TimelineTime.fromMicroseconds(item.us),
        regionIds: [target.stableKey],
        activeBounds: bounds,
        strokeId: StrokeId(item.id),
        sectionId: SectionId('section-${item.id}'),
      ),
    );
  }
  final graph = CompiledSemanticRegionGraph(
    dependencyKey: name,
    worldWidth: 1000,
    worldHeight: 562.5,
    regions: regions,
    containment: const [],
    drawingOrder: const [],
    adjacency: const [],
    attentionEvents: events,
    handFootprint: hand,
  );
  final timeline = CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: ProjectId(name),
      documentRevision: 1,
    ),
    duration: TimelineDuration.fromMicroseconds(durationUs),
    contentEnd: TimelineTime.fromMicroseconds(durationUs),
    drawing: null,
    camera: null,
    audio: const [],
    voiceGuide: null,
    sceneMarkers: const [],
  );
  return (name: name, timeline: timeline, graph: graph, camera: camera);
}

CameraShot _protected(
  String id,
  int startUs,
  CameraAuthorship authorship, {
  bool locked = false,
}) => CameraShot(
  id: CameraShotId(id),
  startTime: TimelineTime.fromMicroseconds(startUs),
  duration: TimelineDuration.fromMicroseconds(600000),
  authorship: authorship,
  isLocked: locked,
  label: id,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('key-$id'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);

String _json(AutoDirectorPlan plan) =>
    const JsonEncoder.withIndent('  ').convert({
      'dependencyKey': plan.inputDependencyKey,
      'status': plan.status.name,
      'shots': [
        for (final shot in plan.proposedShots)
          {
            'id': shot.planId,
            'targets': shot.targetRegionIds,
            'startUs': shot.interval.start.microseconds,
            'endUs': shot.interval.end.microseconds,
            'arrivalUs':
                shot.interval.start.microseconds +
                shot.keyframes.last.offset.microseconds,
            'view': {
              'centerX': shot.keyframes.last.view.centerX,
              'centerY': shot.keyframes.last.view.centerY,
              'viewportWidth': shot.keyframes.last.view.viewportWidth,
            },
            'transition': shot.keyframes.last.incomingTransition.type.name,
            'reasons': shot.reasonCodes.map((value) => value.name).toList()
              ..sort(),
          },
      ],
      'preserved': [
        for (final shot in plan.preservedShots)
          {
            'id': shot.id.value,
            'authorship': shot.authorship.name,
            'locked': shot.isLocked,
          },
      ],
      'diagnostics': plan.diagnostics.map((value) => value.code).toList(),
      'warnings': plan.warnings.map((value) => value.code).toList(),
      'metrics': {
        'shots': plan.qualityMetrics.shotCount,
        'moves': plan.qualityMetrics.moveCount,
        'cuts': plan.qualityMetrics.cutCount,
        'fades': plan.qualityMetrics.fadeCount,
        'averageHoldUs': plan.qualityMetrics.averageHold.microseconds,
        'reversals': plan.qualityMetrics.directionReversals,
        'uncovered': plan.qualityMetrics.uncoveredAttentionEvents,
      },
    });

String _svg(_Fixture fixture, AutoDirectorPlan plan) {
  const panelW = 840.0,
      panelH = 610.0,
      canvasX = 20.0,
      canvasY = 75.0,
      canvasW = 800.0,
      canvasH = 450.0;
  final count = plan.proposedShots.isEmpty ? 1 : plan.proposedShots.length;
  final buffer = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="$panelW" height="${panelH * count}" viewBox="0 0 $panelW ${panelH * count}"><rect width="100%" height="100%" fill="#10151f"/>',
  );
  for (var index = 0; index < count; index++) {
    final shot = plan.proposedShots[index];
    final y0 = index * panelH;
    final view = shot.keyframes.last.view;
    final frameW = canvasW * view.viewportWidth;
    final frameH = frameW / (16 / 9);
    final frameX = canvasX + canvasW * view.centerX - frameW / 2;
    final frameY = y0 + canvasY + canvasH * view.centerY - frameH / 2;
    final safeInsetX = frameW * .12;
    final safeInsetY = frameH * .12;
    buffer.write(
      '<text x="20" y="${y0 + 30}" fill="#fff" font-size="18" font-family="sans-serif">${_escape(fixture.name)} — frame ${index + 1}</text><rect x="$canvasX" y="${y0 + canvasY}" width="$canvasW" height="$canvasH" rx="8" fill="#f7f4ed"/>',
    );
    for (final region in fixture.graph.regions) {
      final x =
          canvasX +
          region.geometricBounds.left / fixture.graph.worldWidth * canvasW;
      final y =
          y0 +
          canvasY +
          region.geometricBounds.top / fixture.graph.worldHeight * canvasH;
      final w =
          (region.geometricBounds.right - region.geometricBounds.left) /
          fixture.graph.worldWidth *
          canvasW;
      final h =
          (region.geometricBounds.bottom - region.geometricBounds.top) /
          fixture.graph.worldHeight *
          canvasH;
      final active = shot.targetRegionIds.contains(region.id);
      buffer.write(
        '<rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="${active ? '#ef8354' : '#78a1bb'}" opacity="${active ? '1' : '.45'}"/><text x="${x + 3}" y="${y + 16}" font-size="11" fill="#111">${_escape(region.target.value)}</text>',
      );
    }
    buffer.write(
      '<rect x="${frameX + safeInsetX}" y="${frameY + safeInsetY}" width="${frameW - safeInsetX * 2}" height="${frameH - safeInsetY * 2}" fill="none" stroke="#f6c85f" stroke-width="2" stroke-dasharray="8 5"/>',
    );
    if (shot.targetRegionIds.isNotEmpty) {
      final target = fixture.graph.regions.firstWhere(
        (region) => region.id == shot.targetRegionIds.first,
      );
      final penX =
          canvasX +
          target.visualBounds.centerX / fixture.graph.worldWidth * canvasW;
      final penY =
          y0 +
          canvasY +
          target.visualBounds.centerY / fixture.graph.worldHeight * canvasH;
      final scale = fixture.graph.handFootprint.screenScale ?? .24;
      final handH = frameH * scale;
      final handW = handH * .8;
      final anchorX = fixture.graph.handFootprint.penTipX ?? .5;
      final anchorY = fixture.graph.handFootprint.penTipY ?? .5;
      buffer.write(
        '<rect x="${penX - anchorX * handW}" y="${penY - anchorY * handH}" width="$handW" height="$handH" fill="#ff4d6d" fill-opacity=".12" stroke="#ff4d6d" stroke-width="2"/><circle cx="$penX" cy="$penY" r="5" fill="#ff4d6d"/><text x="${penX + 8}" y="${penY - 8}" fill="#ff4d6d" font-size="11">pen tip / hand footprint</text>',
      );
    }
    buffer.write(
      '<rect x="$frameX" y="$frameY" width="$frameW" height="$frameH" fill="none" stroke="#30e3ca" stroke-width="4"/><text x="20" y="${y0 + 50}" fill="#a9b8ca" font-size="11" font-family="monospace">encoded/local/world: 0,0..1000,562.5 | visible/semantic: colored bounds | candidate/projected: cyan | safe/text-safe: yellow</text><text x="20" y="${y0 + 555}" fill="#dce6f2" font-size="13" font-family="monospace">target=${_escape(shot.targetRegionIds.join(','))} center=${view.centerX.toStringAsFixed(4)},${view.centerY.toStringAsFixed(4)} viewport=${view.viewportWidth.toStringAsFixed(4)} transition=${shot.keyframes.last.incomingTransition.type.name}</text><text x="20" y="${y0 + 580}" fill="#f6c85f" font-size="13" font-family="monospace">reason=${_escape((shot.reasonCodes.map((value) => value.name).toList()..sort()).join(','))} start=${shot.interval.start.microseconds} arrival=${shot.interval.start.microseconds + shot.keyframes.last.offset.microseconds}</text>',
    );
  }
  return '${buffer.toString()}</svg>';
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
