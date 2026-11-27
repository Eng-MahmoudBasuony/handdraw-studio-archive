import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';

class SceneComposerState {
  const SceneComposerState({
    this.design,
    this.assets = const [],
    this.templates = const [],
    this.selected = 0,
    this.designRevision = 0,
    this.busy = false,
    this.message = '',
  });
  final SceneDesign? design;
  final List<SceneElement> assets;
  final List<SceneDesign> templates;
  final int selected;
  final int designRevision;
  final bool busy;
  final String message;
  SceneComposerState copyWith({
    SceneDesign? design,
    List<SceneElement>? assets,
    List<SceneDesign>? templates,
    int? selected,
    int? designRevision,
    bool? busy,
    String? message,
  }) => SceneComposerState(
    design: design ?? this.design,
    assets: assets ?? this.assets,
    templates: templates ?? this.templates,
    selected: selected ?? this.selected,
    designRevision: designRevision ?? this.designRevision,
    busy: busy ?? this.busy,
    message: message ?? this.message,
  );
}

class SceneComposerCubit extends Cubit<SceneComposerState> {
  SceneComposerCubit(this.assistant, this.library)
    : super(const SceneComposerState());
  final CodexAssistantCubit assistant;
  final SceneLibrary library;
  final _cache = <String, SceneDesign>{};
  Future<void> load() async {
    try {
      final assets = await library.read();
      final templates = await library.scenes();
      if (!isClosed) {
        emit(
          state.copyWith(
            assets: List.unmodifiable(assets),
            templates: List.unmodifiable(templates),
            message: library.diagnostics.isEmpty
                ? ''
                : 'تم تخطي ${library.diagnostics.length} ملفات تالفة / Skipped ${library.diagnostics.length} damaged files',
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            message: 'تعذّر قراءة المكتبة / Could not read library',
          ),
        );
      }
    }
  }

  void show(SceneDesign design) => emit(
    state.copyWith(
      design: design,
      selected: 0,
      designRevision: state.designRevision + 1,
      message: '',
    ),
  );
  void select(int index) => emit(state.copyWith(selected: index));
  void edit(SceneElement element) {
    final d = state.design;
    if (d == null) return;
    final elements = [...d.elements];
    elements[state.selected] = element;
    showEdited(SceneDesign(title: d.title, elements: elements));
  }

  void showEdited(SceneDesign design) =>
      emit(state.copyWith(design: design, message: ''));
  void move(int delta) {
    final d = state.design;
    if (d == null) return;
    final i = state.selected, j = i + delta;
    if (j < 0 || j >= d.elements.length) return;
    final elements = [...d.elements];
    final item = elements.removeAt(i);
    elements.insert(j, item);
    emit(
      state.copyWith(
        design: SceneDesign(title: d.title, elements: elements),
        selected: j,
      ),
    );
  }

  void remove() {
    final d = state.design;
    if (d == null || d.elements.length < 2) return;
    final items = [...d.elements]..removeAt(state.selected);
    emit(
      state.copyWith(
        design: SceneDesign(title: d.title, elements: items),
        selected: 0,
      ),
    );
  }

  void add(SceneElement item) {
    final d = state.design ?? SceneDesign(title: 'My scene', elements: []);
    if (d.elements.length >= 20) return;
    emit(
      state.copyWith(
        design: SceneDesign(
          title: d.title,
          elements: [...d.elements, item.copyWith(newInstance: true)],
        ),
        selected: d.elements.length,
      ),
    );
  }

  Future<void> generate(String prompt) async {
    if (state.busy || prompt.trim().isEmpty) return;
    final key =
        '${assistant.state.model}:$prompt:${state.assets.map((e) => e.assetId).join(',')}';
    if (_cache[key] case final cached?) {
      show(cached);
      return;
    }
    emit(state.copyWith(busy: true, message: ''));
    try {
      final libraryContext = <Map<String, dynamic>>[];
      var contextSize = 0;
      for (final element in state.assets) {
        final json = element.toJson();
        final length = jsonEncode(json).length;
        if (contextSize + length > 12000) continue;
        libraryContext.add(json);
        contextSize += length;
        if (libraryContext.length == 12) break;
      }
      final result = await assistant.design(
        jsonEncode({'request': prompt, 'library': libraryContext}),
        SceneDesign.schema,
      );
      if (isClosed) return;
      if (result == null) {
        emit(
          state.copyWith(
            message:
                'تعذّر التوليد / Generation failed: ${assistant.state.error ?? ""}',
          ),
        );
        return;
      }
      final design = SceneDesign.parse(result);
      _cache[key] = design;
      show(design);
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            message:
                'تعذّر قراءة التصميم. لم يتم تغيير المشروع. / Invalid design; project unchanged.',
          ),
        );
      }
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
  }

  Future<bool> save() async {
    final d = state.design;
    if (d == null) return false;
    try {
      await library.save(d);
      await load();
      if (!isClosed) {
        emit(state.copyWith(message: 'تم الحفظ في المكتبة / Saved to library'));
      }
      return true;
    } catch (_) {
      if (!isClosed) emit(state.copyWith(message: 'تعذّر الحفظ / Save failed'));
      return false;
    }
  }
}
