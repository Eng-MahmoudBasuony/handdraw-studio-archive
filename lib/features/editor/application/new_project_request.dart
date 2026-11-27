import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';

enum NewProjectBackground { transparent, color }

final class NewProjectRequest {
  const NewProjectRequest({
    required this.title,
    required this.width,
    required this.height,
    required this.frameRate,
    this.background = NewProjectBackground.transparent,
    this.defaultImportIntent = ArtworkImportIntent.fullScene,
  });

  final String title;
  final int width;
  final int height;
  final FrameRate frameRate;
  final NewProjectBackground background;
  final ArtworkImportIntent defaultImportIntent;

  bool get isValid =>
      title.trim().isNotEmpty &&
      width >= 64 &&
      height >= 64 &&
      width <= 16384 &&
      height <= 16384;
}
