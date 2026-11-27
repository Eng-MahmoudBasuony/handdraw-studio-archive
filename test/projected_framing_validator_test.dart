import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/projected_framing_validator.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';

void main() {
  const validator = ProjectedFramingValidator();
  const target = SemanticWorldBounds(50, 80, 950, 500);

  test(
    'repairs a cropped target using renderer projection until ratio is 1',
    () {
      const cropped = CameraView(centerX: .5, centerY: .5, viewportWidth: .4);
      expect(
        validator
            .validate(
              view: cropped,
              target: target,
              worldWidth: 1000,
              worldHeight: 562.5,
              safeOutputFraction: .7,
            )
            .projectedSafeContainmentRatio,
        lessThan(1),
      );
      final repaired = validator.repair(
        view: cropped,
        target: target,
        worldWidth: 1000,
        worldHeight: 562.5,
        safeOutputFraction: .7,
        maximumViewportWidth: 2.5,
      );
      final result = validator.validate(
        view: repaired,
        target: target,
        worldWidth: 1000,
        worldHeight: 562.5,
        safeOutputFraction: .7,
      );
      expect(result.projectedSafeContainmentRatio, closeTo(1, 1e-9));
      expect(result.isContained, isTrue);
    },
  );
}
