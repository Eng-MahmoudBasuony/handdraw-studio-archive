import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/smart_scene_splitter.dart';

enum SceneSplitTool { select, lasso, split }

final class SceneSplitState {
  const SceneSplitState({
    this.regions = const [],
    this.selectedIds = const {},
    this.tool = SceneSplitTool.select,
    this.activeGesture = const [],
    this.isSuggesting = false,
    this.hasChanges = false,
    this.canUndo = false,
    this.message,
  });

  final List<SceneRegion> regions;
  final Set<String> selectedIds;
  final SceneSplitTool tool;
  final List<Offset> activeGesture;
  final bool isSuggesting;
  final bool hasChanges;
  final bool canUndo;
  final String? message;

  SceneSplitState copyWith({
    List<SceneRegion>? regions,
    Set<String>? selectedIds,
    SceneSplitTool? tool,
    List<Offset>? activeGesture,
    bool? isSuggesting,
    bool? hasChanges,
    bool? canUndo,
    Object? message = _unset,
  }) => SceneSplitState(
    regions: List.unmodifiable(regions ?? this.regions),
    selectedIds: Set.unmodifiable(selectedIds ?? this.selectedIds),
    tool: tool ?? this.tool,
    activeGesture: List.unmodifiable(activeGesture ?? this.activeGesture),
    isSuggesting: isSuggesting ?? this.isSuggesting,
    hasChanges: hasChanges ?? this.hasChanges,
    canUndo: canUndo ?? this.canUndo,
    message: identical(message, _unset) ? this.message : message as String?,
  );
}

const _unset = Object();

class SceneSplitCubit extends Cubit<SceneSplitState> {
  SceneSplitCubit(this._encoded, [this._splitter = const SmartSceneSplitter()])
    : super(const SceneSplitState());

  final Uint8List _encoded;
  final SmartSceneSplitter _splitter;
  final List<List<SceneRegion>> _undo = [];
  var _nextManualId = 1;
  var _suggestionRevision = 0;
  SmartSceneProposalHandle? _activeSuggestion;

  Future<void> suggest() async {
    if (state.isSuggesting) return;
    final revision = ++_suggestionRevision;
    emit(state.copyWith(isSuggesting: true, message: null));
    final operation = _splitter.start(_encoded);
    _activeSuggestion = operation;
    late final List<SceneRegion> proposed;
    try {
      proposed = await operation.result;
    } on SmartSceneProposalCancelled {
      return;
    } catch (_) {
      if (!isClosed && revision == _suggestionRevision) {
        emit(
          state.copyWith(
            isSuggesting: false,
            message: 'Scene suggestions failed. You can continue with Lasso.',
          ),
        );
      }
      return;
    } finally {
      if (identical(_activeSuggestion, operation)) {
        _activeSuggestion = null;
      }
      await operation.stopped;
    }
    if (isClosed || revision != _suggestionRevision) return;
    if (proposed.isEmpty) {
      emit(
        state.copyWith(
          isSuggesting: false,
          message:
              'No transparent groups were found. Use Lasso to define scenes.',
        ),
      );
      return;
    }
    _remember();
    emit(
      state.copyWith(
        regions: _renumber(proposed),
        selectedIds: {proposed.first.id},
        tool: SceneSplitTool.select,
        activeGesture: const [],
        isSuggesting: false,
        hasChanges: true,
        canUndo: true,
        message: '${proposed.length} scene regions suggested.',
      ),
    );
  }

  void setTool(SceneSplitTool tool) {
    emit(state.copyWith(tool: tool, activeGesture: const [], message: null));
  }

  void select(String id, {bool additive = false}) {
    if (!state.regions.any((region) => region.id == id)) return;
    final selected = additive ? state.selectedIds.toSet() : <String>{};
    if (additive && selected.contains(id)) {
      selected.remove(id);
    } else {
      selected.add(id);
    }
    emit(state.copyWith(selectedIds: selected));
  }

  void beginGesture(Offset point) {
    if (state.tool == SceneSplitTool.select) return;
    emit(state.copyWith(activeGesture: [point]));
  }

  void updateGesture(Offset point) {
    if (state.activeGesture.isEmpty) return;
    if ((point - state.activeGesture.last).distance < 0.003) return;
    emit(state.copyWith(activeGesture: [...state.activeGesture, point]));
  }

  void endGesture() {
    final points = state.activeGesture;
    if (state.tool == SceneSplitTool.lasso) {
      _finishLasso(points);
    } else if (state.tool == SceneSplitTool.split) {
      _finishSplit(points);
    }
  }

  void cancelGesture() {
    if (state.activeGesture.isEmpty) return;
    emit(state.copyWith(activeGesture: const []));
  }

  void _finishLasso(List<Offset> points) {
    if (points.length < 3 || _polygonArea(points).abs() < 0.0002) {
      emit(
        state.copyWith(
          activeGesture: const [],
          message: 'Draw a closed area around the scene.',
        ),
      );
      return;
    }
    _remember();
    final id = 'manual-scene-${_nextManualId++}';
    final region = SceneRegion(
      id: id,
      name: 'Scene ${state.regions.length + 1}',
      polygon: points,
    );
    emit(
      state.copyWith(
        regions: _renumber([...state.regions, region]),
        selectedIds: {id},
        activeGesture: const [],
        tool: SceneSplitTool.lasso,
        hasChanges: true,
        canUndo: true,
        message: 'Manual scene added.',
      ),
    );
  }

  void mergeSelected() {
    final selected = state.regions
        .where((region) => state.selectedIds.contains(region.id))
        .toList(growable: false);
    if (selected.length < 2) return;
    _remember();
    final firstIndex = state.regions.indexOf(selected.first);
    final id = selected.first.id;
    final polygons = [for (final region in selected) ...region.maskPolygons];
    final merged = SceneRegion(
      id: id,
      name: selected.first.name,
      polygon: polygons.first,
      additionalPolygons: polygons.skip(1),
    );
    final regions = state.regions
        .where((region) => !state.selectedIds.contains(region.id))
        .toList();
    regions.insert(firstIndex.clamp(0, regions.length), merged);
    emit(
      state.copyWith(
        regions: _renumber(regions),
        selectedIds: {id},
        hasChanges: true,
        canUndo: true,
        message: '${selected.length} regions merged.',
      ),
    );
  }

  void _finishSplit(List<Offset> points) {
    if (points.length < 2 || state.selectedIds.length != 1) {
      emit(
        state.copyWith(
          activeGesture: const [],
          message: 'Select one region, then draw a line through it.',
        ),
      );
      return;
    }
    final target = state.regions.firstWhere(
      (region) => state.selectedIds.contains(region.id),
    );
    final a = points.first;
    final b = points.last;
    if (!target.bounds.inflate(0.002).contains(a) &&
        !target.bounds.inflate(0.002).contains(b) &&
        !_lineIntersectsRect(a, b, target.bounds)) {
      emit(
        state.copyWith(
          activeGesture: const [],
          message: 'The split line must cross the selected region.',
        ),
      );
      return;
    }
    final left = <List<Offset>>[];
    final right = <List<Offset>>[];
    for (final polygon in target.maskPolygons) {
      final pieces = _isConvex(polygon) ? [polygon] : _triangulate(polygon);
      for (final piece in pieces) {
        final negative = _clipPolygonToHalfPlane(
          piece,
          a,
          b,
          keepNegative: true,
        );
        final positive = _clipPolygonToHalfPlane(
          piece,
          a,
          b,
          keepNegative: false,
        );
        if (negative.length >= 3 && _polygonArea(negative).abs() > 0.000001) {
          left.add(negative);
        }
        if (positive.length >= 3 && _polygonArea(positive).abs() > 0.000001) {
          right.add(positive);
        }
      }
    }
    if (left.isEmpty || right.isEmpty) {
      emit(
        state.copyWith(
          activeGesture: const [],
          message: 'The split line must divide the selected mask.',
        ),
      );
      return;
    }
    _remember();
    final first = _regionFromPolygons(left, id: target.id);
    final second = _regionFromPolygons(right);
    final index = state.regions.indexOf(target);
    final regions = [...state.regions]
      ..replaceRange(index, index + 1, [first, second]);
    emit(
      state.copyWith(
        regions: _renumber(regions),
        selectedIds: {first.id},
        activeGesture: const [],
        tool: SceneSplitTool.select,
        hasChanges: true,
        canUndo: true,
        message: 'Region split into two scenes.',
      ),
    );
  }

  SceneRegion _regionFromPolygons(List<List<Offset>> polygons, {String? id}) {
    return SceneRegion(
      id: id ?? 'manual-scene-${_nextManualId++}',
      name: 'Scene',
      polygon: polygons.first,
      additionalPolygons: polygons.skip(1),
    );
  }

  void removeSelected() {
    if (state.selectedIds.isEmpty) return;
    _remember();
    emit(
      state.copyWith(
        regions: _renumber(
          state.regions
              .where((region) => !state.selectedIds.contains(region.id))
              .toList(growable: false),
        ),
        selectedIds: const {},
        hasChanges: true,
        canUndo: true,
        message: 'Selected regions removed.',
      ),
    );
  }

  /// Clears the current draft and immediately switches to manual authoring.
  ///
  /// The regions are still remembered by the local undo stack, so this is a
  /// reversible editing choice rather than a destructive project operation.
  void clearForManualLasso() {
    _suggestionRevision++;
    _cancelActiveSuggestion();
    final hadRegions = state.regions.isNotEmpty;
    if (hadRegions) _remember();
    emit(
      state.copyWith(
        regions: const [],
        selectedIds: const {},
        activeGesture: const [],
        tool: SceneSplitTool.lasso,
        isSuggesting: false,
        hasChanges: state.hasChanges || hadRegions,
        canUndo: state.canUndo || hadRegions,
        message: 'Suggestions cleared. Draw scenes with Lasso.',
      ),
    );
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= state.regions.length) {
      return;
    }
    _remember();
    final regions = [...state.regions];
    if (newIndex > oldIndex) newIndex--;
    final moved = regions.removeAt(oldIndex);
    regions.insert(newIndex.clamp(0, regions.length), moved);
    emit(
      state.copyWith(
        regions: _renumber(regions),
        hasChanges: true,
        canUndo: true,
      ),
    );
  }

  void undo() {
    if (_undo.isEmpty) return;
    final regions = _undo.removeLast();
    emit(
      state.copyWith(
        regions: _renumber(regions),
        selectedIds: const {},
        activeGesture: const [],
        tool: SceneSplitTool.select,
        hasChanges: _undo.isNotEmpty,
        canUndo: _undo.isNotEmpty,
        message: 'Last scene edit undone.',
      ),
    );
  }

  void _remember() {
    _undo.add(state.regions);
    if (_undo.length > 30) _undo.removeAt(0);
  }

  List<SceneRegion> _renumber(List<SceneRegion> source) => List.unmodifiable([
    for (var index = 0; index < source.length; index++)
      source[index].copyWith(name: 'Scene ${index + 1}'),
  ]);

  void _cancelActiveSuggestion() {
    final operation = _activeSuggestion;
    _activeSuggestion = null;
    if (operation != null) unawaited(operation.cancel());
  }

  @override
  Future<void> close() async {
    _suggestionRevision++;
    final operation = _activeSuggestion;
    _activeSuggestion = null;
    if (operation != null) await operation.cancel();
    return super.close();
  }
}

double _polygonArea(List<Offset> points) {
  var area = 0.0;
  for (var index = 0; index < points.length; index++) {
    final a = points[index];
    final b = points[(index + 1) % points.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area / 2;
}

double _side(Offset a, Offset b, Offset point) =>
    (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);

List<Offset> _clipPolygonToHalfPlane(
  List<Offset> polygon,
  Offset lineStart,
  Offset lineEnd, {
  required bool keepNegative,
}) {
  if (polygon.length < 3) return const [];
  bool inside(Offset point) {
    final value = _side(lineStart, lineEnd, point);
    return keepNegative ? value <= 0.0000001 : value >= -0.0000001;
  }

  Offset intersection(Offset from, Offset to) {
    final fromSide = _side(lineStart, lineEnd, from);
    final toSide = _side(lineStart, lineEnd, to);
    final denominator = fromSide - toSide;
    if (denominator.abs() < 0.000000001) return from;
    final t = (fromSide / denominator).clamp(0.0, 1.0);
    return Offset.lerp(from, to, t)!;
  }

  final output = <Offset>[];
  var previous = polygon.last;
  var previousInside = inside(previous);
  for (final current in polygon) {
    final currentInside = inside(current);
    if (currentInside != previousInside) {
      output.add(intersection(previous, current));
    }
    if (currentInside) output.add(current);
    previous = current;
    previousInside = currentInside;
  }
  return output;
}

bool _isConvex(List<Offset> polygon) {
  if (polygon.length < 4) return true;
  double? sign;
  for (var index = 0; index < polygon.length; index++) {
    final cross = _side(
      polygon[index],
      polygon[(index + 1) % polygon.length],
      polygon[(index + 2) % polygon.length],
    );
    if (cross.abs() < 0.000000001) continue;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

List<List<Offset>> _triangulate(List<Offset> polygon) {
  if (polygon.length < 3) return const [];
  final indices = List<int>.generate(polygon.length, (index) => index);
  final result = <List<Offset>>[];
  final orientation = _polygonArea(polygon).sign;
  var guard = polygon.length * polygon.length;
  while (indices.length > 3 && guard-- > 0) {
    var clipped = false;
    for (var cursor = 0; cursor < indices.length; cursor++) {
      final previous = indices[(cursor - 1) % indices.length];
      final current = indices[cursor];
      final next = indices[(cursor + 1) % indices.length];
      final a = polygon[previous];
      final b = polygon[current];
      final c = polygon[next];
      final turn = _side(a, b, c);
      if (turn.abs() < 0.000000001 || turn.sign != orientation) continue;
      var containsVertex = false;
      for (final candidate in indices) {
        if (candidate == previous ||
            candidate == current ||
            candidate == next) {
          continue;
        }
        if (_pointInTriangle(polygon[candidate], a, b, c)) {
          containsVertex = true;
          break;
        }
      }
      if (containsVertex) continue;
      result.add([a, b, c]);
      indices.removeAt(cursor);
      clipped = true;
      break;
    }
    if (!clipped) break;
  }
  if (indices.length == 3) {
    result.add([for (final index in indices) polygon[index]]);
  }
  return result.isEmpty ? [polygon] : result;
}

bool _pointInTriangle(Offset point, Offset a, Offset b, Offset c) {
  final d1 = _side(a, b, point);
  final d2 = _side(b, c, point);
  final d3 = _side(c, a, point);
  final hasNegative =
      d1 < -0.000000001 || d2 < -0.000000001 || d3 < -0.000000001;
  final hasPositive = d1 > 0.000000001 || d2 > 0.000000001 || d3 > 0.000000001;
  return !(hasNegative && hasPositive);
}

bool _lineIntersectsRect(Offset a, Offset b, Rect rect) {
  if (rect.contains(a) || rect.contains(b)) return true;
  final sides = [
    (rect.topLeft, rect.topRight),
    (rect.topRight, rect.bottomRight),
    (rect.bottomRight, rect.bottomLeft),
    (rect.bottomLeft, rect.topLeft),
  ];
  for (final edge in sides) {
    final d1 = _side(a, b, edge.$1);
    final d2 = _side(a, b, edge.$2);
    final d3 = _side(edge.$1, edge.$2, a);
    final d4 = _side(edge.$1, edge.$2, b);
    if (d1 * d2 <= 0 && d3 * d4 <= 0) return true;
  }
  return false;
}
