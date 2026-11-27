import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/presentation/inspector/application/inspector_cubit.dart';

void main() {
  test('inspector navigation is isolated from project state', () {
    final cubit = InspectorCubit();
    addTearDown(cubit.close);

    expect(cubit.state, InspectorTab.project);
    cubit.select(InspectorTab.animation);
    expect(cubit.state, InspectorTab.animation);
    cubit.select(InspectorTab.audio);
    expect(cubit.state, InspectorTab.audio);
  });
}
