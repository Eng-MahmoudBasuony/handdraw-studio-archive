import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

extension type const DocumentSemanticFingerprint(String value) {
  static final RegExp _canonical = RegExp(r'^sha256:[0-9a-f]{64}$');

  bool get isCanonical => _canonical.hasMatch(value);
}

extension type const DocumentPersistenceFingerprint(String value) {
  static final RegExp _canonical = RegExp(r'^sha256:[0-9a-f]{64}$');

  bool get isCanonical => _canonical.hasMatch(value);
}

final class DocumentFingerprints {
  const DocumentFingerprints({
    required this.semantic,
    required this.persistence,
  });

  final DocumentSemanticFingerprint semantic;
  final DocumentPersistenceFingerprint persistence;
}

abstract interface class DocumentFingerprintCalculator {
  DocumentFingerprints calculate(ProjectDocument document);
}
