import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

ProjectDocument projectDocumentParityFixture() {
  final artworkId = ProjectAssetId('asset-art');
  final handId = ProjectAssetId('asset-hand');
  final voiceId = ProjectAssetId('asset-voice');
  final strokeId = StrokeId('stroke-title');
  final sectionId = SectionId('section-title');
  final trackId = AudioTrackId('audio-voice');
  return ProjectDocument(
    id: ProjectId('project-parity'),
    title: 'Runtime parity',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.fromMicroseconds(5000000),
    artworkAssetId: artworkId,
    handConfiguration: ProjectHandConfiguration(
      assetId: handId,
      presetId: 'custom-hand',
      scale: 0.3,
    ),
    assets: [
      ProjectAsset(
        id: artworkId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'lesson.svg',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:art',
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
      ),
      ProjectAsset(
        id: handId,
        kind: ProjectAssetKind.hand,
        originalFileName: 'hand.png',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:hand',
        mediaType: 'image/png',
      ),
      ProjectAsset(
        id: voiceId,
        kind: ProjectAssetKind.audio,
        originalFileName: 'voice.wav',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:voice',
        mediaType: 'audio/wav',
        mediaDuration: TimelineDuration.fromMicroseconds(4000000),
      ),
    ],
    strokes: [
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: 'Title',
        points: const [DocumentPoint(0.1, 0.2), DocumentPoint(0.8, 0.2)],
        assetId: artworkId,
        isTextShape: true,
        reversed: true,
      ),
    ],
    sections: [
      ProjectSection(
        id: sectionId,
        name: 'Title',
        strokeIds: [strokeId],
        assetId: artworkId,
        timing: DocumentSectionTiming(
          pauseAfter: TimelineDuration.fromMicroseconds(250000),
          audioCueAnchor: AudioCueAnchor(
            audioTrackId: trackId,
            sourceMediaTime: TimelineTime.fromMicroseconds(750000),
          ),
        ),
      ),
    ],
    sectionOrder: [sectionId],
    scenes: [
      ProjectScene(
        id: SceneId('scene-title'),
        name: 'Title scene',
        sectionIds: [sectionId],
        locked: false,
      ),
    ],
    audioTracks: [
      ProjectAudioTrack(
        id: trackId,
        assetId: voiceId,
        start: TimelineTime.zero,
        duration: TimelineDuration.fromMicroseconds(4000000),
        exportPolicy: AudioExportPolicy.referenceOnly,
      ),
    ],
    voiceGuide: ProjectVoiceGuide(
      audioTrackId: trackId,
      displayName: 'Narration',
      originalFileName: 'voice.wav',
    ),
  );
}
