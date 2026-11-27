import 'package:flutter_bloc/flutter_bloc.dart';

enum InspectorTab { project, animation, hand, audio }

/// Owns transient Inspector navigation only. Project mutations remain in
/// EditorCubit so preview and export continue to share one source of truth.
class InspectorCubit extends Cubit<InspectorTab> {
  InspectorCubit() : super(InspectorTab.project);

  void select(InspectorTab tab) {
    if (tab != state) emit(tab);
  }
}
