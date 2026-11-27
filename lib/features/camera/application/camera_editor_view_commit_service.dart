import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';

/// Commits the camera frame currently visible in the editor before playback.
///
/// Both the shot Preview command and the master video player use this service,
/// so the camera border cannot describe a different crop from the rendered
/// Preview or MOV snapshot.
final class CameraEditorViewCommitService {
  const CameraEditorViewCommitService();

  bool commitIfDirty({
    required EditorCubit editor,
    required CameraEditingCubit editing,
  }) {
    final editingState = editing.state;
    if (!editingState.isEditorViewDirty) return true;
    final shotId = editingState.primaryShotId;
    if (shotId == null) return true;
    CameraShot? selectedShot;
    for (final shot in editor.state.document.cameraTrack?.shots ?? const []) {
      if (shot.id == shotId) {
        selectedShot = shot;
        break;
      }
    }
    if (selectedShot == null || selectedShot.keyframes.isEmpty) return false;
    final selectedFrameId = editingState.selectedKeyframeId;
    var selectedFrame = selectedShot.keyframes.last;
    if (selectedFrameId != null) {
      for (final frame in selectedShot.keyframes) {
        if (frame.id == selectedFrameId) {
          selectedFrame = frame;
          break;
        }
      }
    }
    final updated = selectedShot.ownerSceneId == null
        ? editor.updateSimpleCameraView(
            selectedShot.id,
            editingState.editorView,
          )
        : editor.setCameraKeyframeView(
            selectedShot.id,
            selectedFrame.id,
            editingState.editorView,
          );
    if (!updated) return false;
    editing.markEditorViewSaved();
    return true;
  }
}
