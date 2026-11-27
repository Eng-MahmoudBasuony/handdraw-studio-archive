import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_value_list.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

/// Permanent development-schema codec, deliberately independent from File IO.
///
/// The manifest contains references and metadata only. Asset bytes belong to a
/// future archive/container layer and are never encoded as Base64 here.
final class DevelopmentProjectManifestCodec {
  const DevelopmentProjectManifestCodec({
    this.validator = const ProjectDocumentValidator(),
  });

  static const schema = 'handdraw-development-manifest';
  static const schemaVersion = 0;
  static const developmentRevision = 15;
  static const _compatibleDevelopmentRevisions = {
    11,
    12,
    13,
    14,
    developmentRevision,
  };

  final ProjectDocumentValidator validator;

  Map<String, Object?> encode(ProjectDocument document) {
    validator.validate(document).throwIfInvalid();
    return {
      'schema': schema,
      'schemaVersion': schemaVersion,
      'developmentRevision': developmentRevision,
      'project': {
        'id': document.id.value,
        'title': document.title,
        'canvas': {
          'width': document.canvas.width,
          'height': document.canvas.height,
          'background': _canvasBackground(document.canvas.background),
        },
        'frameRate': {
          'numerator': document.frameRate.numerator,
          'denominator': document.frameRate.denominator,
        },
        'durationUs': document.duration.microseconds,
        'creationDefaults': {
          'background': document.creationDefaults.background.name,
          'importIntent': document.creationDefaults.importIntent.name,
        },
        'pathProcessing': document.pathProcessingMetadata == null
            ? null
            : _pathProcessing(document.pathProcessingMetadata!),
        'artworkAssetId': document.artworkAssetId?.value,
        'artworkPlacement': document.artworkPlacement == null
            ? null
            : {
                'encodedBounds': _encodeRect(
                  document.artworkPlacement!.encodedBounds,
                ),
                'visibleBounds': _encodeRect(
                  document.artworkPlacement!.visibleBounds,
                ),
                'destination': _encodeRect(
                  document.artworkPlacement!.destination,
                ),
                'mode': document.artworkPlacement!.mode.name,
                'importIntent': document.artworkPlacement!.importIntent.name,
              },
        'export': {
          'presetId': document.exportConfiguration.presetId.name,
          'alphaMode': document.exportConfiguration.alphaMode.name,
          'renderQuality': document.exportConfiguration.renderQuality.name,
        },
        'motion': {
          'drawingDurationUs':
              document.motionConfiguration.drawingDuration.microseconds,
          'drawingSpeed': document.motionConfiguration.drawingSpeed,
          'penTravelSpeed': document.motionConfiguration.penTravelSpeed,
          'startDelayUs': document.motionConfiguration.startDelay.microseconds,
          'endHoldUs': document.motionConfiguration.endHold.microseconds,
          'revealWidth': document.motionConfiguration.revealWidth,
          'imageAnimationEffect':
              document.motionConfiguration.imageAnimationEffect,
          'showDrawingHand': document.motionConfiguration.showDrawingHand,
        },
        'hand': {
          'assetId': document.handConfiguration.assetId?.value,
          'presetId': document.handConfiguration.presetId,
          'scale': document.handConfiguration.scale,
          'rotationDegrees': document.handConfiguration.rotationDegrees,
          'flipX': document.handConfiguration.flipX,
          'penTip': [
            document.handConfiguration.penTip.x,
            document.handConfiguration.penTip.y,
          ],
        },
        'writingSound': {
          'enabled': document.writingSoundConfiguration.enabled,
          'preset': document.writingSoundConfiguration.preset.name,
          'volume': document.writingSoundConfiguration.volume,
        },
        'assets': [for (final asset in document.assets) _asset(asset)],
        'strokes': [for (final stroke in document.strokes) _stroke(stroke)],
        'sections': [
          for (final section in document.sections) _section(section),
        ],
        'sectionOrder': [for (final id in document.sectionOrder) id.value],
        'scenes': [for (final scene in document.scenes) _scene(scene)],
        'audioTracks': [
          for (final track in document.audioTracks) _audio(track),
        ],
        'voiceGuide': document.voiceGuide == null
            ? null
            : _voiceGuide(document.voiceGuide!),
        'cameraTrack': document.cameraTrack == null
            ? null
            : _cameraTrack(document.cameraTrack!),
        'timeline': _timeline(document.timeline),
        'contentMetadata': _contentMetadata(document.contentMetadata),
        'autoDirectorSettings': _autoDirectorSettings(
          document.autoDirectorSettings,
        ),
      },
    };
  }

  ProjectDocument decode(Map<String, Object?> manifest) {
    if (manifest['schema'] != schema ||
        manifest['schemaVersion'] != schemaVersion ||
        !_compatibleDevelopmentRevisions.contains(
          manifest['developmentRevision'],
        )) {
      throw const FormatException('Unsupported development project format');
    }
    final project = _map(manifest['project'], 'project');
    final clipPolygonInterner = _ClipPolygonInterner();
    final exclusionBoundsInterner = _ExclusionBoundsInterner();
    try {
      final document = ProjectDocument(
        id: ProjectId(_string(project['id'], 'project.id')),
        title: _string(project['title'], 'project.title'),
        canvas: _canvas(project['canvas']),
        frameRate: _frameRate(project['frameRate']),
        duration: TimelineDuration.fromMicroseconds(
          _integer(project['durationUs'], 'project.durationUs'),
        ),
        creationDefaults: _decodeCreationDefaults(project['creationDefaults']),
        pathProcessingMetadata: _decodePathProcessing(
          project['pathProcessing'],
        ),
        artworkAssetId: _optionalId(
          project['artworkAssetId'],
          ProjectAssetId.new,
          'project.artworkAssetId',
        ),
        artworkPlacement: _decodeArtworkPlacement(project['artworkPlacement']),
        exportConfiguration: _decodeExport(project['export']),
        motionConfiguration: _decodeMotion(project['motion']),
        handConfiguration: _decodeHand(project['hand']),
        writingSoundConfiguration: _decodeWritingSound(project['writingSound']),
        assets: [
          for (final raw in _list(project['assets'], 'project.assets'))
            _decodeAsset(raw),
        ],
        strokes: [
          for (final raw in _list(project['strokes'], 'project.strokes'))
            _decodeStroke(raw, clipPolygonInterner, exclusionBoundsInterner),
        ],
        sections: [
          for (final raw in _list(project['sections'], 'project.sections'))
            _decodeSection(raw),
        ],
        sectionOrder: [
          for (final raw in _list(
            project['sectionOrder'],
            'project.sectionOrder',
          ))
            SectionId(_string(raw, 'sectionOrder[]')),
        ],
        scenes: [
          for (final raw in _list(project['scenes'], 'project.scenes'))
            _decodeScene(raw),
        ],
        audioTracks: [
          for (final raw in _list(
            project['audioTracks'],
            'project.audioTracks',
          ))
            _decodeAudio(raw),
        ],
        voiceGuide: project['voiceGuide'] == null
            ? null
            : _decodeVoiceGuide(project['voiceGuide']),
        cameraTrack: project['cameraTrack'] == null
            ? null
            : _decodeCameraTrack(project['cameraTrack']),
        timeline: _decodeTimeline(project['timeline']),
        contentMetadata: _decodeContentMetadata(project['contentMetadata']),
        autoDirectorSettings: _decodeAutoDirectorSettings(
          project['autoDirectorSettings'],
        ),
      );
      validator.validate(document).throwIfInvalid();
      return document;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid development project manifest: $error');
    }
  }

  ProjectCreationDefaults _decodeCreationDefaults(Object? raw) {
    if (raw == null) return const ProjectCreationDefaults();
    final map = _map(raw, 'project.creationDefaults');
    return ProjectCreationDefaults(
      background: ProjectCanvasBackground.values.firstWhere(
        (value) => value.name == map['background'],
        orElse: () => ProjectCanvasBackground.transparent,
      ),
      importIntent: ArtworkImportIntent.values.firstWhere(
        (value) => value.name == map['importIntent'],
        orElse: () => ArtworkImportIntent.fullScene,
      ),
    );
  }

  Map<String, Object?> _pathProcessing(
    ProjectPathProcessingMetadata metadata,
  ) => {
    'engineId': metadata.engineId,
    'algorithmVersion': metadata.algorithmVersion,
    'featureSet': metadata.featureSet,
    'processingParameters': metadata.processingParameters,
    'sourceAssetHash': metadata.sourceAssetHash,
  };

  ProjectPathProcessingMetadata? _decodePathProcessing(Object? raw) {
    if (raw == null) return null;
    final map = _map(raw, 'project.pathProcessing');
    final features = _list(
      map['featureSet'],
      'project.pathProcessing.featureSet',
    ).map((item) => _string(item, 'pathProcessing.featureSet[]')).toSet();
    final parameters = _map(
      map['processingParameters'],
      'project.pathProcessing.processingParameters',
    );
    final frameDetection = features.contains('suspected-frame-detection-v1');
    return ProjectPathProcessingMetadata(
      engineId: _string(map['engineId'], 'pathProcessing.engineId'),
      algorithmVersion: _integer(
        map['algorithmVersion'],
        'pathProcessing.algorithmVersion',
      ),
      sourceAssetHash: _string(
        map['sourceAssetHash'],
        'pathProcessing.sourceAssetHash',
      ),
      suspectedFrameDetection: frameDetection,
      suspectedFrameConfidenceThreshold: frameDetection
          ? _double(
              parameters['suspectedFrameConfidenceThreshold'],
              'pathProcessing.processingParameters.suspectedFrameConfidenceThreshold',
            )
          : 0.96,
    );
  }

  Map<String, Object?> _autoDirectorSettings(
    ProjectAutoDirectorSettings settings,
  ) => {
    'presetId': settings.presetId.name,
    'presetVersion': settings.presetVersion,
    'customOverrides': {
      'motionAmount': settings.customOverrides.motionAmount?.name,
      'framing': settings.customOverrides.framing?.name,
      'textEmphasis': settings.customOverrides.textEmphasis,
      'minimumHoldUs': settings.customOverrides.minimumHold?.inMicroseconds,
      'transitionPreference':
          settings.customOverrides.transitionPreference?.name,
      'allowMovementDuringDrawing':
          settings.customOverrides.allowMovementDuringDrawing,
      'overviewFrequency': settings.customOverrides.overviewFrequency?.name,
      'handSafeFraming': settings.customOverrides.handSafeFraming,
    },
  };

  ProjectAutoDirectorSettings _decodeAutoDirectorSettings(Object? raw) {
    final map = _map(raw, 'autoDirectorSettings');
    final overrides = _map(
      map['customOverrides'],
      'autoDirectorSettings.customOverrides',
    );
    T? optionalEnum<T extends Enum>(
      Object? value,
      List<T> values,
      String path,
    ) => value == null ? null : _enumValue(values, value, path);
    return ProjectAutoDirectorSettings(
      presetId: _enumValue(
        AutoDirectorPresetId.values,
        map['presetId'],
        'autoDirectorSettings.presetId',
      ),
      presetVersion: _integer(
        map['presetVersion'],
        'autoDirectorSettings.presetVersion',
      ),
      customOverrides: AutoDirectorCustomOverrides(
        motionAmount: optionalEnum(
          overrides['motionAmount'],
          DirectorMotionAmount.values,
          'autoDirectorSettings.customOverrides.motionAmount',
        ),
        framing: optionalEnum(
          overrides['framing'],
          DirectorFraming.values,
          'autoDirectorSettings.customOverrides.framing',
        ),
        textEmphasis: overrides['textEmphasis'] == null
            ? null
            : _double(
                overrides['textEmphasis'],
                'autoDirectorSettings.customOverrides.textEmphasis',
              ),
        minimumHold: overrides['minimumHoldUs'] == null
            ? null
            : Duration(
                microseconds: _integer(
                  overrides['minimumHoldUs'],
                  'autoDirectorSettings.customOverrides.minimumHoldUs',
                ),
              ),
        transitionPreference: optionalEnum(
          overrides['transitionPreference'],
          DirectorTransitionPreference.values,
          'autoDirectorSettings.customOverrides.transitionPreference',
        ),
        allowMovementDuringDrawing:
            overrides['allowMovementDuringDrawing'] == null
            ? null
            : _boolean(
                overrides['allowMovementDuringDrawing'],
                'autoDirectorSettings.customOverrides.allowMovementDuringDrawing',
              ),
        overviewFrequency: optionalEnum(
          overrides['overviewFrequency'],
          DirectorOverviewFrequency.values,
          'autoDirectorSettings.customOverrides.overviewFrequency',
        ),
        handSafeFraming: overrides['handSafeFraming'] == null
            ? null
            : _boolean(
                overrides['handSafeFraming'],
                'autoDirectorSettings.customOverrides.handSafeFraming',
              ),
      ),
    );
  }

  Map<String, Object?> _contentMetadata(ProjectContentMetadata metadata) => {
    'projectLocaleHint': metadata.projectLocaleHint,
    'entities': [
      for (final entity in metadata.entities)
        {
          'target': {
            'kind': entity.target.kind.name,
            'id': entity.target.value,
          },
          'contentRole': entity.contentRole?.name,
          'importance': entity.importance.name,
          'keepTogether': entity.keepTogether,
          'cameraExcluded': entity.cameraExcluded,
          'textSensitive': entity.textSensitive,
          'minimumPreferredZoom': entity.minimumPreferredZoom?.value,
          'provenance': entity.provenance.name,
          'textMetadata': entity.textMetadata == null
              ? null
              : {
                  'originalText': entity.textMetadata!.originalText,
                  'direction': entity.textMetadata!.direction.name,
                  'directionProvenance':
                      entity.textMetadata!.directionProvenance.name,
                  'languageHint': entity.textMetadata!.languageHint,
                  'fontSize': entity.textMetadata!.fontSize,
                  'lineCount': entity.textMetadata!.lineCount,
                  'sourceKind': entity.textMetadata!.sourceKind.name,
                  'sourceProvenance': entity.textMetadata!.sourceProvenance,
                },
        },
    ],
  };

  ProjectContentMetadata _decodeContentMetadata(Object? raw) {
    final map = _map(raw, 'project.contentMetadata');
    return ProjectContentMetadata(
      projectLocaleHint: _optionalString(
        map['projectLocaleHint'],
        'contentMetadata.projectLocaleHint',
      ),
      entities: [
        for (final item in _list(map['entities'], 'contentMetadata.entities'))
          _decodeEntitySemanticMetadata(item),
      ],
    );
  }

  EntitySemanticMetadata _decodeEntitySemanticMetadata(Object? raw) {
    final map = _map(raw, 'contentMetadata.entity');
    final target = _map(map['target'], 'contentMetadata.entity.target');
    final textRaw = map['textMetadata'];
    return EntitySemanticMetadata(
      target: SemanticTargetReference.decoded(
        _enumValue(
          SemanticTargetKind.values,
          target['kind'],
          'semanticTarget.kind',
        ),
        _string(target['id'], 'semanticTarget.id'),
      ),
      contentRole: map['contentRole'] == null
          ? null
          : _enumValue(
              SemanticContentRole.values,
              map['contentRole'],
              'semantic.contentRole',
            ),
      importance: _enumValue(
        SemanticImportance.values,
        map['importance'],
        'semantic.importance',
      ),
      keepTogether: _boolean(map['keepTogether'], 'semantic.keepTogether'),
      cameraExcluded: _boolean(
        map['cameraExcluded'],
        'semantic.cameraExcluded',
      ),
      textSensitive: _boolean(map['textSensitive'], 'semantic.textSensitive'),
      minimumPreferredZoom: map['minimumPreferredZoom'] == null
          ? null
          : PreferredSemanticZoom(
              _double(
                map['minimumPreferredZoom'],
                'semantic.minimumPreferredZoom',
              ),
            ),
      provenance: _enumValue(
        SemanticMetadataProvenance.values,
        map['provenance'],
        'semantic.provenance',
      ),
      textMetadata: textRaw == null ? null : _decodeTextMetadata(textRaw),
    );
  }

  ImportedTextMetadata _decodeTextMetadata(Object? raw) {
    final map = _map(raw, 'semantic.textMetadata');
    final original = _optionalString(
      map['originalText'],
      'textMetadata.originalText',
    );
    if (original != null && original.length > 16384) {
      throw const FormatException('Text metadata exceeds 16384 characters.');
    }
    return ImportedTextMetadata(
      originalText: original,
      direction: _enumValue(
        KnownTextDirection.values,
        map['direction'],
        'textMetadata.direction',
      ),
      directionProvenance: _enumValue(
        DirectionProvenance.values,
        map['directionProvenance'],
        'textMetadata.directionProvenance',
      ),
      languageHint: _optionalString(
        map['languageHint'],
        'textMetadata.languageHint',
      ),
      fontSize: _optionalDouble(map['fontSize'], 'textMetadata.fontSize'),
      lineCount: _optionalInteger(map['lineCount'], 'textMetadata.lineCount'),
      sourceKind: _enumValue(
        TextSourceKind.values,
        map['sourceKind'],
        'textMetadata.sourceKind',
      ),
      sourceProvenance: _string(
        map['sourceProvenance'],
        'textMetadata.sourceProvenance',
      ),
    );
  }

  Map<String, Object?> _cameraTrack(ProjectCameraTrack track) => {
    'id': track.id.value,
    'enabled': track.enabled,
    'defaultView': _cameraView(track.defaultView),
    'shots': [
      for (final shot in track.shots)
        {
          'id': shot.id.value,
          'startUs': shot.startTime.microseconds,
          'durationUs': shot.duration.microseconds,
          'authorship': shot.authorship.name,
          'isLocked': shot.isLocked,
          'label': shot.label,
          'ownerSceneId': shot.ownerSceneId?.value,
          'sceneConnection': shot.sceneConnection.name,
          'keyframes': [
            for (final keyframe in shot.keyframes)
              {
                'id': keyframe.id.value,
                'offsetUs': keyframe.offset.microseconds,
                'view': _cameraView(keyframe.view),
                'transition': {
                  'type': keyframe.incomingTransition.type.name,
                  'durationUs':
                      keyframe.incomingTransition.duration.microseconds,
                  'easing': keyframe.incomingTransition.easing.name,
                },
              },
          ],
        },
    ],
  };

  Map<String, Object?> _cameraView(CameraView view) => {
    'centerX': view.centerX,
    'centerY': view.centerY,
    'viewportWidth': view.viewportWidth,
  };

  ProjectCameraTrack _decodeCameraTrack(Object? raw) {
    final map = _map(raw, 'cameraTrack');
    return ProjectCameraTrack(
      id: CameraTrackId(_string(map['id'], 'cameraTrack.id')),
      enabled: _boolean(map['enabled'], 'cameraTrack.enabled'),
      defaultView: _decodeCameraView(map['defaultView']),
      shots: [
        for (final rawShot in _list(map['shots'], 'cameraTrack.shots'))
          _decodeCameraShot(rawShot),
      ],
    );
  }

  CameraShot _decodeCameraShot(Object? raw) {
    final map = _map(raw, 'cameraShot');
    return CameraShot(
      id: CameraShotId(_string(map['id'], 'cameraShot.id')),
      startTime: TimelineTime.fromMicroseconds(
        _integer(map['startUs'], 'cameraShot.startUs'),
      ),
      duration: TimelineDuration.fromMicroseconds(
        _integer(map['durationUs'], 'cameraShot.durationUs'),
      ),
      authorship: _enumValue(
        CameraAuthorship.values,
        map['authorship'],
        'cameraShot.authorship',
      ),
      isLocked: _boolean(map['isLocked'], 'cameraShot.isLocked'),
      label: map['label'] == null
          ? null
          : _string(map['label'], 'cameraShot.label'),
      ownerSceneId: map['ownerSceneId'] == null
          ? null
          : SceneId(_string(map['ownerSceneId'], 'cameraShot.ownerSceneId')),
      sceneConnection: map['sceneConnection'] == null
          ? CameraSceneConnection.cut
          : _enumValue(
              CameraSceneConnection.values,
              map['sceneConnection'],
              'cameraShot.sceneConnection',
            ),
      keyframes: [
        for (final rawKeyframe in _list(
          map['keyframes'],
          'cameraShot.keyframes',
        ))
          _decodeCameraKeyframe(rawKeyframe),
      ],
    );
  }

  CameraKeyframe _decodeCameraKeyframe(Object? raw) {
    final map = _map(raw, 'cameraKeyframe');
    final transition = _map(map['transition'], 'cameraKeyframe.transition');
    return CameraKeyframe(
      id: CameraKeyframeId(_string(map['id'], 'cameraKeyframe.id')),
      offset: TimelineTime.fromMicroseconds(
        _integer(map['offsetUs'], 'cameraKeyframe.offsetUs'),
      ),
      view: _decodeCameraView(map['view']),
      incomingTransition: CameraTransition(
        type: _enumValue(
          CameraTransitionType.values,
          transition['type'],
          'cameraTransition.type',
        ),
        duration: TimelineDuration.fromMicroseconds(
          _integer(transition['durationUs'], 'cameraTransition.durationUs'),
        ),
        easing: _enumValue(
          CameraEasing.values,
          transition['easing'],
          'cameraTransition.easing',
        ),
      ),
    );
  }

  CameraView _decodeCameraView(Object? raw) {
    final map = _map(raw, 'cameraView');
    return CameraView(
      centerX: _double(map['centerX'], 'cameraView.centerX'),
      centerY: _double(map['centerY'], 'cameraView.centerY'),
      viewportWidth: _double(map['viewportWidth'], 'cameraView.viewportWidth'),
    );
  }

  Map<String, Object?> _asset(ProjectAsset asset) => {
    'id': asset.id.value,
    'kind': asset.kind.name,
    'originalFileName': asset.originalFileName,
    'storagePolicy': asset.storagePolicy.name,
    'artworkSourceType': asset.artworkSourceType?.name,
    'externalLocator': asset.externalLocator == null
        ? null
        : {
            'pathHint': asset.externalLocator!.pathHint,
            'securityBookmark': asset.externalLocator!.securityBookmark,
          },
    'mediaDurationUs': asset.mediaDuration?.microseconds,
    'mediaType': asset.mediaType,
    'contentHash': asset.contentHash,
  };

  Map<String, Object?> _stroke(ProjectStroke stroke) => {
    'id': stroke.id.value,
    'sectionId': stroke.sectionId.value,
    'name': stroke.name,
    'assetId': stroke.assetId?.value,
    'points': [
      for (final point in stroke.points) [point.x, point.y],
    ],
    'geometry': stroke.geometry?.toJson(),
    'animationGeometry': stroke.animationGeometry?.toJson(),
    'isFilledShape': stroke.isFilledShape,
    'isTextShape': stroke.isTextShape,
    'isGlobalDecoration': stroke.isGlobalDecoration,
    'fillColorValue': stroke.fillColorValue,
    'hidden': stroke.hidden,
    'reversed': stroke.reversed,
    'revealOnly': stroke.revealOnly,
    'isPaintStroke': stroke.isPaintStroke,
    'paintRegion': stroke.paintRegion,
    'revealStyle': stroke.revealStyle.name,
    'clipBounds': stroke.clipBounds == null
        ? null
        : _encodeRect(stroke.clipBounds!),
    'clipPolygons': [
      for (final polygon in stroke.clipPolygons)
        [
          for (final point in polygon) [point.x, point.y],
        ],
    ],
    'exclusionBounds': [
      for (final rect in stroke.exclusionBounds) _encodeRect(rect),
    ],
    'revealWidth': stroke.revealWidth,
    'pausePoints': [
      for (final pause in stroke.pausePoints)
        {
          'id': pause.id.value,
          'progress': pause.progress,
          'durationUs': pause.duration.microseconds,
          'keepHandVisible': pause.keepHandVisible,
        },
    ],
    'vectorMaskStrokes': [
      for (final mask in stroke.vectorMaskStrokes)
        {
          'geometry': mask.geometry.toJson(),
          'width': mask.width,
          'erase': mask.erase,
          'feather': mask.feather,
          'clipToLayer': mask.clipToLayer,
        },
    ],
  };

  List<double> _encodeRect(DocumentRect rect) => [
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
  ];

  ProjectArtworkPlacement? _decodeArtworkPlacement(Object? raw) {
    if (raw == null) return null;
    final map = _map(raw, 'project.artworkPlacement');
    return ProjectArtworkPlacement(
      encodedBounds: _decodeRect(
        map['encodedBounds'],
        'project.artworkPlacement.encodedBounds',
      ),
      visibleBounds: _decodeRect(
        map['visibleBounds'],
        'project.artworkPlacement.visibleBounds',
      ),
      destination: _decodeRect(
        map['destination'],
        'project.artworkPlacement.destination',
      ),
      mode: ArtworkPlacementMode.values.firstWhere(
        (value) => value.name == map['mode'],
        orElse: () => ArtworkPlacementMode.fitEntire,
      ),
      importIntent: ArtworkImportIntent.values.firstWhere(
        (value) => value.name == map['importIntent'],
        orElse: () => ArtworkImportIntent.fullScene,
      ),
    );
  }

  Map<String, Object?> _section(ProjectSection section) => {
    'id': section.id.value,
    'name': section.name,
    'strokeIds': [for (final id in section.strokeIds) id.value],
    'assetId': section.assetId?.value,
    'timing': {
      'animationDurationUs': section.timing.animationDuration?.microseconds,
      'pauseBeforeUs': section.timing.pauseBefore.microseconds,
      'pauseBeforeEnabled':
          section.timing.pauseBeforeEnabled ||
          !section.timing.pauseBefore.isZero,
      'pauseAfterUs': section.timing.pauseAfter.microseconds,
      'pauseAfterEnabled':
          section.timing.pauseAfterEnabled || !section.timing.pauseAfter.isZero,
      'transitionAfterUs': section.timing.transitionAfter.microseconds,
      'speedMultiplier': section.timing.speedMultiplier,
      'pauseHandBehavior': section.timing.pauseHandBehavior.name,
      'audioCueAnchor': section.timing.audioCueAnchor == null
          ? null
          : {
              'audioTrackId': section.timing.audioCueAnchor!.audioTrackId.value,
              'sourceMediaTimeUs':
                  section.timing.audioCueAnchor!.sourceMediaTime.microseconds,
            },
      'handEntranceAnimation': section.timing.handEntranceAnimation.name,
      'handEntranceDurationUs':
          section.timing.handEntranceDuration.microseconds,
      'handExitAnimation': section.timing.handExitAnimation.name,
      'handExitDurationUs': section.timing.handExitDuration.microseconds,
      'keepHandVisibleAfterDrawing': section.timing.keepHandVisibleAfterDrawing,
    },
  };

  Map<String, Object?> _scene(ProjectScene scene) => {
    'id': scene.id.value,
    'name': scene.name,
    'sectionIds': [for (final id in scene.sectionIds) id.value],
    'locked': scene.locked,
  };

  Map<String, Object?> _audio(ProjectAudioTrack track) => {
    'id': track.id.value,
    'assetId': track.assetId.value,
    'startUs': track.start.microseconds,
    'durationUs': track.duration.microseconds,
    'sourceOffsetUs': track.sourceOffset.microseconds,
    'exportPolicy': track.exportPolicy.name,
    'muted': track.muted,
    'affectsTimelineDuration': track.affectsTimelineDuration,
  };

  Map<String, Object?> _timeline(PersistentTimeline timeline) => {
    'drawing': {'enabled': timeline.drawing.enabled},
    'camera': {
      'enabled': timeline.camera.enabled,
      'cameraTrackId': timeline.camera.cameraTrackId?.value,
    },
    'audio': [
      for (final track in timeline.audio)
        {'audioTrackId': track.audioTrackId.value},
    ],
    'voiceGuide': timeline.voiceGuide == null
        ? null
        : {'audioTrackId': timeline.voiceGuide!.audioTrackId.value},
    'sceneMarkers': [
      for (final marker in timeline.sceneMarkers)
        {'sceneId': marker.sceneId.value, 'timeUs': marker.time.microseconds},
    ],
    'leadingHoldUs': timeline.leadingHold.microseconds,
    'trailingHoldUs': timeline.trailingHold.microseconds,
  };

  Map<String, Object?> _voiceGuide(ProjectVoiceGuide guide) => {
    'audioTrackId': guide.audioTrackId.value,
    'displayName': guide.displayName,
    'originalFileName': guide.originalFileName,
  };

  ProjectAsset _decodeAsset(Object? raw) {
    final map = _map(raw, 'asset');
    return ProjectAsset(
      id: ProjectAssetId(_string(map['id'], 'asset.id')),
      kind: _enumValue(ProjectAssetKind.values, map['kind'], 'asset.kind'),
      originalFileName: _string(
        map['originalFileName'],
        'asset.originalFileName',
      ),
      storagePolicy: _enumValue(
        ProjectAssetStoragePolicy.values,
        map['storagePolicy'],
        'asset.storagePolicy',
      ),
      contentHash: _string(map['contentHash'], 'asset.contentHash'),
      mediaType: _optionalString(map['mediaType'], 'asset.mediaType'),
      artworkSourceType: map['artworkSourceType'] == null
          ? null
          : _enumValue(
              ArtworkSourceType.values,
              map['artworkSourceType'],
              'asset.artworkSourceType',
            ),
      externalLocator: map['externalLocator'] == null
          ? null
          : _decodeExternalLocator(map['externalLocator']),
      mediaDuration: map['mediaDurationUs'] == null
          ? null
          : TimelineDuration.fromMicroseconds(
              _integer(map['mediaDurationUs'], 'asset.mediaDurationUs'),
            ),
    );
  }

  ProjectStroke _decodeStroke(
    Object? raw,
    _ClipPolygonInterner clipPolygonInterner,
    _ExclusionBoundsInterner exclusionBoundsInterner,
  ) {
    final map = _map(raw, 'stroke');
    final clipPolygons = clipPolygonInterner.intern([
      for (final rawPolygon in _list(
        map['clipPolygons'] ?? const [],
        'stroke.clipPolygons',
      ))
        [
          for (final rawPoint in _list(rawPolygon, 'stroke.clipPolygons[]'))
            _point(rawPoint),
        ],
    ]);
    return ProjectStroke(
      id: StrokeId(_string(map['id'], 'stroke.id')),
      sectionId: SectionId(_string(map['sectionId'], 'stroke.sectionId')),
      name: _string(map['name'], 'stroke.name'),
      assetId: _optionalId(
        map['assetId'],
        ProjectAssetId.new,
        'stroke.assetId',
      ),
      points: [
        for (final rawPoint in _list(map['points'], 'stroke.points'))
          _point(rawPoint),
      ],
      geometry: _geometry(map['geometry'], 'stroke.geometry'),
      animationGeometry: _geometry(
        map['animationGeometry'],
        'stroke.animationGeometry',
      ),
      isFilledShape: _boolean(map['isFilledShape'], 'stroke.isFilledShape'),
      isTextShape: _boolean(map['isTextShape'], 'stroke.isTextShape'),
      isGlobalDecoration: _boolean(
        map['isGlobalDecoration'],
        'stroke.isGlobalDecoration',
      ),
      fillColorValue: _optionalInteger(
        map['fillColorValue'],
        'stroke.fillColorValue',
      ),
      hidden: _boolean(map['hidden'], 'stroke.hidden'),
      reversed: _boolean(map['reversed'], 'stroke.reversed'),
      revealOnly: _boolean(map['revealOnly'], 'stroke.revealOnly'),
      isPaintStroke: map['isPaintStroke'] as bool? ?? false,
      paintRegion: map['paintRegion'] as int? ?? 0,
      revealStyle: _enumValue(
        DocumentRevealStyle.values,
        map['revealStyle'],
        'stroke.revealStyle',
      ),
      clipBounds: map['clipBounds'] == null
          ? null
          : _decodeRect(map['clipBounds'], 'stroke.clipBounds'),
      clipPolygons: clipPolygons,
      exclusionBounds: exclusionBoundsInterner.intern([
        for (final rect in _list(
          map['exclusionBounds'],
          'stroke.exclusionBounds',
        ))
          _decodeRect(rect, 'stroke.exclusionBounds[]'),
      ]),
      revealWidth: _optionalDouble(map['revealWidth'], 'stroke.revealWidth'),
      pausePoints: [
        for (final pause in _list(map['pausePoints'], 'stroke.pausePoints'))
          _decodePause(pause),
      ],
      vectorMaskStrokes: [
        for (final mask in _list(
          map['vectorMaskStrokes'],
          'stroke.vectorMaskStrokes',
        ))
          _decodeMask(mask),
      ],
    );
  }

  ProjectSection _decodeSection(Object? raw) {
    final map = _map(raw, 'section');
    final timing = _map(map['timing'], 'section.timing');
    final animationUs = timing['animationDurationUs'];
    return ProjectSection(
      id: SectionId(_string(map['id'], 'section.id')),
      name: _string(map['name'], 'section.name'),
      strokeIds: [
        for (final id in _list(map['strokeIds'], 'section.strokeIds'))
          StrokeId(_string(id, 'section.strokeIds[]')),
      ],
      assetId: _optionalId(
        map['assetId'],
        ProjectAssetId.new,
        'section.assetId',
      ),
      timing: DocumentSectionTiming(
        animationDuration: animationUs == null
            ? null
            : TimelineDuration.fromMicroseconds(
                _integer(animationUs, 'animationDurationUs'),
              ),
        pauseBefore: _duration(timing, 'pauseBeforeUs'),
        pauseBeforeEnabled:
            timing['pauseBeforeEnabled'] as bool? ??
            _duration(timing, 'pauseBeforeUs').microseconds > 0,
        pauseAfter: _duration(timing, 'pauseAfterUs'),
        pauseAfterEnabled:
            timing['pauseAfterEnabled'] as bool? ??
            _duration(timing, 'pauseAfterUs').microseconds > 0,
        transitionAfter: _duration(timing, 'transitionAfterUs'),
        speedMultiplier: _double(
          timing['speedMultiplier'],
          'section.timing.speedMultiplier',
        ),
        pauseHandBehavior: _enumValue(
          DocumentPauseHandBehavior.values,
          timing['pauseHandBehavior'],
          'section.timing.pauseHandBehavior',
        ),
        audioCueAnchor: timing['audioCueAnchor'] == null
            ? null
            : _decodeAudioCueAnchor(timing['audioCueAnchor']),
        handEntranceAnimation: timing['handEntranceAnimation'] == null
            ? SectionHandEntranceAnimation.none
            : _enumValue(
                SectionHandEntranceAnimation.values,
                timing['handEntranceAnimation'],
                'section.timing.handEntranceAnimation',
              ),
        handEntranceDuration: timing['handEntranceDurationUs'] == null
            ? TimelineDuration.zero
            : _duration(timing, 'handEntranceDurationUs'),
        handExitAnimation: timing['handExitAnimation'] == null
            ? SectionHandExitAnimation.none
            : _enumValue(
                SectionHandExitAnimation.values,
                timing['handExitAnimation'],
                'section.timing.handExitAnimation',
              ),
        handExitDuration: timing['handExitDurationUs'] == null
            ? TimelineDuration.zero
            : _duration(timing, 'handExitDurationUs'),
        keepHandVisibleAfterDrawing:
            timing['keepHandVisibleAfterDrawing'] as bool? ?? false,
      ),
    );
  }

  ProjectScene _decodeScene(Object? raw) {
    final map = _map(raw, 'scene');
    return ProjectScene(
      id: SceneId(_string(map['id'], 'scene.id')),
      name: _string(map['name'], 'scene.name'),
      sectionIds: [
        for (final id in _list(map['sectionIds'], 'scene.sectionIds'))
          SectionId(_string(id, 'scene.sectionIds[]')),
      ],
      locked: _boolean(map['locked'], 'scene.locked'),
    );
  }

  ProjectAudioTrack _decodeAudio(Object? raw) {
    final map = _map(raw, 'audioTrack');
    return ProjectAudioTrack(
      id: AudioTrackId(_string(map['id'], 'audioTrack.id')),
      assetId: ProjectAssetId(_string(map['assetId'], 'audioTrack.assetId')),
      start: TimelineTime.fromMicroseconds(
        _integer(map['startUs'], 'audioTrack.startUs'),
      ),
      duration: TimelineDuration.fromMicroseconds(
        _integer(map['durationUs'], 'audioTrack.durationUs'),
      ),
      sourceOffset: TimelineTime.fromMicroseconds(
        _integer(map['sourceOffsetUs'], 'audioTrack.sourceOffsetUs'),
      ),
      exportPolicy: _enumValue(
        AudioExportPolicy.values,
        map['exportPolicy'],
        'audioTrack.exportPolicy',
      ),
      muted: _boolean(map['muted'], 'audioTrack.muted'),
      affectsTimelineDuration: _boolean(
        map['affectsTimelineDuration'],
        'audioTrack.affectsTimelineDuration',
      ),
    );
  }

  PersistentTimeline _decodeTimeline(Object? raw) {
    final map = _map(raw, 'timeline');
    final drawing = _map(map['drawing'], 'timeline.drawing');
    final camera = _map(map['camera'], 'timeline.camera');
    final cameraEnabled = _boolean(
      camera['enabled'],
      'timeline.camera.enabled',
    );
    return PersistentTimeline(
      drawing: PersistentDrawingTimelineTrack(
        enabled: _boolean(drawing['enabled'], 'timeline.drawing.enabled'),
      ),
      camera: cameraEnabled
          ? PersistentCameraTimelineTrack.enabled(
              cameraTrackId: CameraTrackId(
                _string(
                  camera['cameraTrackId'],
                  'timeline.camera.cameraTrackId',
                ),
              ),
            )
          : const PersistentCameraTimelineTrack.disabled(),
      audio: [
        for (final item in _list(map['audio'], 'timeline.audio'))
          PersistentAudioTimelineTrack(
            audioTrackId: AudioTrackId(
              _string(
                _map(item, 'timeline.audio[]')['audioTrackId'],
                'timeline.audio[].audioTrackId',
              ),
            ),
          ),
      ],
      voiceGuide: map['voiceGuide'] == null
          ? null
          : PersistentVoiceGuideTimelineTrack(
              audioTrackId: AudioTrackId(
                _string(
                  _map(
                    map['voiceGuide'],
                    'timeline.voiceGuide',
                  )['audioTrackId'],
                  'timeline.voiceGuide.audioTrackId',
                ),
              ),
            ),
      sceneMarkers: [
        for (final item in _list(map['sceneMarkers'], 'timeline.sceneMarkers'))
          PersistentSceneMarker(
            sceneId: SceneId(
              _string(
                _map(item, 'timeline.sceneMarkers[]')['sceneId'],
                'timeline.sceneMarkers[].sceneId',
              ),
            ),
            time: TimelineTime.fromMicroseconds(
              _integer(
                _map(item, 'timeline.sceneMarkers[]')['timeUs'],
                'timeline.sceneMarkers[].timeUs',
              ),
            ),
          ),
      ],
      leadingHold: TimelineDuration.fromMicroseconds(
        _integer(map['leadingHoldUs'], 'timeline.leadingHoldUs'),
      ),
      trailingHold: TimelineDuration.fromMicroseconds(
        _integer(map['trailingHoldUs'], 'timeline.trailingHoldUs'),
      ),
    );
  }

  ExternalAssetLocator _decodeExternalLocator(Object? raw) {
    final map = _map(raw, 'asset.externalLocator');
    return ExternalAssetLocator(
      pathHint: _string(map['pathHint'], 'externalLocator.pathHint'),
      securityBookmark: _optionalString(
        map['securityBookmark'],
        'externalLocator.securityBookmark',
      ),
    );
  }

  AudioCueAnchor _decodeAudioCueAnchor(Object? raw) {
    final map = _map(raw, 'section.timing.audioCueAnchor');
    return AudioCueAnchor(
      audioTrackId: AudioTrackId(
        _string(map['audioTrackId'], 'audioCueAnchor.audioTrackId'),
      ),
      sourceMediaTime: TimelineTime.fromMicroseconds(
        _integer(map['sourceMediaTimeUs'], 'audioCueAnchor.sourceMediaTimeUs'),
      ),
    );
  }

  ProjectVoiceGuide _decodeVoiceGuide(Object? raw) {
    final map = _map(raw, 'project.voiceGuide');
    return ProjectVoiceGuide(
      audioTrackId: AudioTrackId(
        _string(map['audioTrackId'], 'voiceGuide.audioTrackId'),
      ),
      displayName: _string(map['displayName'], 'voiceGuide.displayName'),
      originalFileName: _string(
        map['originalFileName'],
        'voiceGuide.originalFileName',
      ),
    );
  }

  ProjectExportConfiguration _decodeExport(Object? raw) {
    final map = _map(raw, 'project.export');
    return ProjectExportConfiguration(
      presetId: _enumValue(
        ExportPresetId.values,
        map['presetId'],
        'export.presetId',
      ),
      alphaMode: _enumValue(
        ExportAlphaMode.values,
        map['alphaMode'],
        'export.alphaMode',
      ),
      renderQuality: _enumValue(
        ExportRenderQuality.values,
        map['renderQuality'],
        'export.renderQuality',
      ),
    );
  }

  ProjectMotionConfiguration _decodeMotion(Object? raw) {
    final map = _map(raw, 'project.motion');
    return ProjectMotionConfiguration(
      drawingDuration: _duration(map, 'drawingDurationUs'),
      drawingSpeed: _double(map['drawingSpeed'], 'motion.drawingSpeed'),
      penTravelSpeed: _double(map['penTravelSpeed'], 'motion.penTravelSpeed'),
      startDelay: _duration(map, 'startDelayUs'),
      endHold: _duration(map, 'endHoldUs'),
      revealWidth: _double(map['revealWidth'], 'motion.revealWidth'),
      imageAnimationEffect: map['imageAnimationEffect'] as String? ?? 'legacy',
      showDrawingHand: map['showDrawingHand'] as bool? ?? true,
    );
  }

  ProjectHandConfiguration _decodeHand(Object? raw) {
    final map = _map(raw, 'project.hand');
    return ProjectHandConfiguration(
      assetId: _optionalId(map['assetId'], ProjectAssetId.new, 'hand.assetId'),
      presetId: _optionalString(map['presetId'], 'hand.presetId'),
      scale: _double(map['scale'], 'hand.scale'),
      rotationDegrees: _double(map['rotationDegrees'], 'hand.rotationDegrees'),
      flipX: _boolean(map['flipX'], 'hand.flipX'),
      penTip: _point(map['penTip']),
    );
  }

  ProjectWritingSoundConfiguration _decodeWritingSound(Object? raw) {
    final map = _map(raw, 'project.writingSound');
    return ProjectWritingSoundConfiguration(
      enabled: _boolean(map['enabled'], 'writingSound.enabled'),
      preset: _enumValue(
        WritingSoundPreset.values,
        map['preset'],
        'writingSound.preset',
      ),
      volume: _double(map['volume'], 'writingSound.volume'),
    );
  }

  ProjectCanvas _canvas(Object? raw) {
    final map = _map(raw, 'project.canvas');
    return ProjectCanvas(
      width: _integer(map['width'], 'canvas.width'),
      height: _integer(map['height'], 'canvas.height'),
      background: _decodeCanvasBackground(map['background']),
    );
  }

  Map<String, Object?> _canvasBackground(CanvasBackground background) => {
    'mode': background.mode.name,
    'colorValue': background.colorValue,
    'preset': background.preset?.name,
  };

  CanvasBackground _decodeCanvasBackground(Object? raw) {
    if (raw == null) return const CanvasBackground.transparent();
    final map = _map(raw, 'canvas.background');
    final mode = _enumValue(
      CanvasBackgroundMode.values,
      map['mode'],
      'canvas.background.mode',
    );
    return switch (mode) {
      CanvasBackgroundMode.transparent => const CanvasBackground.transparent(),
      CanvasBackgroundMode.solid => CanvasBackground.solid(
        _integer(map['colorValue'], 'canvas.background.colorValue'),
      ).normalized(),
      CanvasBackgroundMode.preset => CanvasBackground.preset(
        _enumValue(
          CanvasBackgroundPreset.values,
          map['preset'],
          'canvas.background.preset',
        ),
      ),
    };
  }

  FrameRate _frameRate(Object? raw) {
    final map = _map(raw, 'project.frameRate');
    return FrameRate(
      numerator: _integer(map['numerator'], 'frameRate.numerator'),
      denominator: _integer(map['denominator'], 'frameRate.denominator'),
    );
  }

  DocumentPoint _point(Object? raw) {
    final values = _list(raw, 'point');
    if (values.length != 2 || values[0] is! num || values[1] is! num) {
      throw const FormatException('A point must contain two numeric values.');
    }
    return DocumentPoint(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
    );
  }

  StrokePathGeometry? _geometry(Object? raw, String path) =>
      raw == null ? null : StrokePathGeometry.fromJson(_map(raw, path));

  DocumentRect _decodeRect(Object? raw, String path) {
    final values = _list(raw, path);
    if (values.length != 4) {
      throw FormatException('$path must contain four numeric values.');
    }
    return DocumentRect(
      left: _double(values[0], '$path.left'),
      top: _double(values[1], '$path.top'),
      right: _double(values[2], '$path.right'),
      bottom: _double(values[3], '$path.bottom'),
    );
  }

  DocumentStrokePause _decodePause(Object? raw) {
    final map = _map(raw, 'stroke.pausePoint');
    return DocumentStrokePause(
      id: StrokePauseId(_string(map['id'], 'pausePoint.id')),
      progress: _double(map['progress'], 'pausePoint.progress'),
      duration: TimelineDuration.fromMicroseconds(
        _integer(map['durationUs'], 'pausePoint.durationUs'),
      ),
      keepHandVisible: _boolean(
        map['keepHandVisible'],
        'pausePoint.keepHandVisible',
      ),
    );
  }

  DocumentVectorMaskStroke _decodeMask(Object? raw) {
    final map = _map(raw, 'stroke.vectorMaskStroke');
    return DocumentVectorMaskStroke(
      geometry: StrokePathGeometry.fromJson(
        _map(map['geometry'], 'vectorMaskStroke.geometry'),
      ),
      width: _double(map['width'], 'vectorMaskStroke.width'),
      erase: _boolean(map['erase'], 'vectorMaskStroke.erase'),
      feather: _double(map['feather'], 'vectorMaskStroke.feather'),
      clipToLayer: _boolean(map['clipToLayer'], 'vectorMaskStroke.clipToLayer'),
    );
  }

  TimelineDuration _duration(Map<String, Object?> map, String key) =>
      TimelineDuration.fromMicroseconds(_integer(map[key], key));

  T? _optionalId<T>(Object? raw, T Function(String) create, String path) =>
      raw == null ? null : create(_string(raw, path));

  T _enumValue<T extends Enum>(List<T> values, Object? raw, String path) {
    final name = _string(raw, path);
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => throw FormatException('Unknown $path: $name.'),
    );
  }

  Map<String, Object?> _map(Object? raw, String path) {
    if (raw is! Map) throw FormatException('$path must be an object.');
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  List<Object?> _list(Object? raw, String path) {
    if (raw is! List) throw FormatException('$path must be a list.');
    return raw.cast<Object?>();
  }

  String _string(Object? raw, String path) {
    if (raw is! String || raw.trim().isEmpty) {
      throw FormatException('$path must be a non-empty string.');
    }
    return raw.trim();
  }

  String? _optionalString(Object? raw, String path) =>
      raw == null ? null : _string(raw, path);

  int _integer(Object? raw, String path) {
    if (raw is! int) throw FormatException('$path must be an integer.');
    return raw;
  }

  int? _optionalInteger(Object? raw, String path) =>
      raw == null ? null : _integer(raw, path);

  double? _optionalDouble(Object? raw, String path) =>
      raw == null ? null : _double(raw, path);

  double _double(Object? raw, String path) {
    if (raw is! num || !raw.toDouble().isFinite) {
      throw FormatException('$path must be a finite number.');
    }
    return raw.toDouble();
  }

  bool _boolean(Object? raw, String path) {
    if (raw is! bool) throw FormatException('$path must be a boolean.');
    return raw;
  }
}

final class _ClipPolygonInterner {
  final Map<String, ImmutablePolygonList<DocumentPoint>> _bySignature = {};

  ImmutablePolygonList<DocumentPoint> intern(
    List<List<DocumentPoint>> polygons,
  ) {
    if (polygons.isEmpty) {
      return ImmutablePolygonList<DocumentPoint>.freeze(const []);
    }
    final signature = StringBuffer();
    for (final polygon in polygons) {
      signature.write('${polygon.length}:');
      for (final point in polygon) {
        signature
          ..write(point.x.toStringAsPrecision(17))
          ..write(',')
          ..write(point.y.toStringAsPrecision(17))
          ..write(';');
      }
      signature.write('|');
    }
    return _bySignature.putIfAbsent(
      signature.toString(),
      () => ImmutablePolygonList<DocumentPoint>.freeze(polygons),
    );
  }
}

final class _ExclusionBoundsInterner {
  final Map<String, ImmutableValueList<DocumentRect>> _bySignature = {};

  ImmutableValueList<DocumentRect> intern(List<DocumentRect> bounds) {
    final signature = StringBuffer();
    for (final rect in bounds) {
      signature
        ..write(rect.left.toStringAsPrecision(17))
        ..write(',')
        ..write(rect.top.toStringAsPrecision(17))
        ..write(',')
        ..write(rect.right.toStringAsPrecision(17))
        ..write(',')
        ..write(rect.bottom.toStringAsPrecision(17))
        ..write(';');
    }
    return _bySignature.putIfAbsent(
      signature.toString(),
      () => ImmutableValueList.freeze(bounds),
    );
  }
}
