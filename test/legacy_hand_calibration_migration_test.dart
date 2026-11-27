import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/legacy_hand_calibration_migration.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  const migration = LegacyHandCalibrationMigration();
  ProjectDocument document({
    String? presetId = 'marker-technical-wheat-right',
    DocumentPoint penTip = const DocumentPoint(0.18, 0.72),
    String fileName = 'technical-pen-wheat-right-v1.png',
  }) {
    final base = projectDocumentParityFixture();
    final handAssetId = base.handConfiguration.assetId;
    return base.copyWith(
      handConfiguration: base.handConfiguration.copyWith(
        presetId: presetId,
        penTip: penTip,
      ),
      assets: [
        for (final asset in base.assets)
          if (asset.id == handAssetId)
            asset.copyWith(originalFileName: fileName)
          else
            asset,
      ],
    );
  }

  test('repairs generic marker anchor on the bundled Technical Pen', () {
    final migrated = migration.migrate(document());
    expect(
      migrated.handConfiguration.penTip,
      const DocumentPoint(0.114583, 0.485677),
    );
    expect(migrated.handConfiguration.scale, 0.30);
  });

  test('preserves a deliberate Technical Pen scale', () {
    final source = document().copyWith(
      handConfiguration: document().handConfiguration.copyWith(scale: 0.42),
    );

    expect(migration.migrate(source).handConfiguration.scale, 0.42);
  });

  test('recognizes an old Technical Pen asset even without preset id', () {
    final migrated = migration.migrate(document(presetId: null));
    expect(
      migrated.handConfiguration.penTip,
      const DocumentPoint(0.114583, 0.485677),
    );
  });

  test('repairs the implicit Technical Pen used by old empty projects', () {
    final base = projectDocumentParityFixture();
    final legacy = base.copyWith(
      handConfiguration: const ProjectHandConfiguration(
        presetId: null,
        assetId: null,
        penTip: DocumentPoint(0.18, 0.72),
      ),
    );

    final migrated = migration.migrate(legacy);

    expect(
      migrated.handConfiguration.penTip,
      const DocumentPoint(0.114583, 0.485677),
    );
  });

  test(
    'preserves deliberate calibration and repairs generic built-in tips',
    () {
      const custom = DocumentPoint(0.21, 0.61);
      expect(
        migration.migrate(document(penTip: custom)).handConfiguration.penTip,
        custom,
      );
      expect(
        migration
            .migrate(
              document(
                presetId: 'marker-dark-right',
                fileName: 'marker-dark-right-v1.png',
              ),
            )
            .handConfiguration
            .penTip,
        const DocumentPoint(0.115234, 0.648926),
      );
    },
  );

  test('repairs every previously shipped bundled anchor', () {
    const cases = {
      'marker-right': (
        DocumentPoint(0.18, 0.72),
        DocumentPoint(0.161458, 0.111328),
      ),
      'marker-left': (
        DocumentPoint(0.18, 0.72),
        DocumentPoint(0.161458, 0.111328),
      ),
      'marker-compact': (
        DocumentPoint(0.18, 0.72),
        DocumentPoint(0.161458, 0.111328),
      ),
      'marker-dark-right': (
        DocumentPoint(0.115, 0.642),
        DocumentPoint(0.115234, 0.648926),
      ),
      'marker-fineliner-right': (
        DocumentPoint(0.150, 0.563),
        DocumentPoint(0.149089, 0.568848),
      ),
      'marker-blue-right': (
        DocumentPoint(0.190, 0.563),
        DocumentPoint(0.189453, 0.568359),
      ),
      'marker-front-black-right': (
        DocumentPoint(0.376, 0.045),
        DocumentPoint(0.376953, 0.045898),
      ),
      'marker-technical-wheat-right': (
        DocumentPoint(0.115, 0.488),
        DocumentPoint(0.114583, 0.485677),
      ),
    };

    for (final entry in cases.entries) {
      final migrated = migration.migrate(
        document(presetId: entry.key, penTip: entry.value.$1),
      );
      expect(migrated.handConfiguration.penTip, entry.value.$2);
    }
  });

  test('repairs a decoded cross-preset anchor but preserves custom points', () {
    final wrongTechnicalTip = DocumentPoint(
      double.parse('0.114583'),
      double.parse('0.485677'),
    );
    final repaired = migration.migrate(
      document(
        presetId: 'marker-right',
        penTip: wrongTechnicalTip,
        fileName: 'hand-writing-marker.png',
      ),
    );

    expect(
      repaired.handConfiguration.penTip,
      const DocumentPoint(0.161458, 0.111328),
    );

    const custom = DocumentPoint(0.237, 0.419);
    expect(
      migration
          .migrate(
            document(
              presetId: 'marker-right',
              penTip: custom,
              fileName: 'hand-writing-marker.png',
            ),
          )
          .handConfiguration
          .penTip,
      custom,
    );
  });
}
