import 'package:handdraw_studio/features/path_document/domain/models/path_document.dart';

class PathValidationIssue {
  const PathValidationIssue(this.pathId, this.message);

  final String pathId;
  final String message;
}

class PathValidationService {
  const PathValidationService();

  List<PathValidationIssue> validate(PathDocument document) {
    final issues = <PathValidationIssue>[];
    final ids = <String>{};
    for (final path in document.paths) {
      if (!ids.add(path.id)) {
        issues.add(PathValidationIssue(path.id, 'Path id must be unique.'));
      }
      if (path.geometry.isEmpty) {
        issues.add(
          PathValidationIssue(path.id, 'Path has no drawable segments.'),
        );
      }
      if (path.revealBehavior.widthFraction <= 0 ||
          !path.revealBehavior.widthFraction.isFinite) {
        issues.add(
          PathValidationIssue(path.id, 'Reveal width must be positive.'),
        );
      }
    }
    return List.unmodifiable(issues);
  }
}
