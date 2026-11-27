import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/asset_entry_naming_policy.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/atomic_file_replacer.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/raw_zip_entry_scanner.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';

final class KoniProjectContainerStore implements ProjectContainerStore {
  const KoniProjectContainerStore({
    this.limits = const ProjectContainerLimits(),
    this.naming = const AssetEntryNamingPolicy(),
    this.codec = const DevelopmentProjectManifestCodec(),
    this.documentValidator = const ProjectDocumentValidator(),
    this.atomicReplacer = const QualifiedAtomicFileReplacer(),
  });

  final ProjectContainerLimits limits;
  final AssetEntryNamingPolicy naming;
  final DevelopmentProjectManifestCodec codec;
  final ProjectDocumentValidator documentValidator;
  final AtomicFileReplacer atomicReplacer;

  @override
  Future<void> save({
    required ProjectContainerLocation destination,
    required ProjectDocument document,
    required ProjectAssetSourceCatalog assetSources,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async {
    final target = File(destination.path);
    atomicReplacer.ensureSupported();
    await target.parent.create(recursive: true);
    final scope = atomicReplacer is ScopedAtomicFileReplacer
        ? atomicReplacer as ScopedAtomicFileReplacer
        : null;
    final temporary = scope != null
        ? await scope.prepare(target)
        : File(
            '${target.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
          );
    ArchiveWriter? writer;
    FileByteSink? sink;
    try {
      _throwIfCancelled(cancellation);
      _report(
        onProgress,
        const ProjectContainerProgress(
          stage: ProjectContainerStage.validating,
          completedBytes: 0,
          totalBytes: 0,
        ),
      );
      documentValidator.validate(document).throwIfInvalid();
      final embedded = document.assets
          .where(
            (asset) =>
                asset.storagePolicy == ProjectAssetStoragePolicy.embedded,
          )
          .toList(growable: false);
      if (embedded.length + 1 > limits.maxEntryCount) {
        throw ProjectContainerException(
          ProjectContainerFailureCode.limitExceeded,
          'Project exceeds ${limits.maxEntryCount} container entries.',
        );
      }
      final mappings = <ProjectAssetId, AssetEntryMapping>{};
      final sources = <ProjectAssetId, ProjectAssetByteSource>{};
      final sourceLengths = <ProjectAssetId, int>{};
      var sourceBytes = 0;
      if (!limits.allowedCompressionMethods.contains(
        ProjectContainerCompressionMethod.deflate,
      )) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.unsupportedFeature,
          'The active container limits do not allow the manifest compression.',
        );
      }
      for (final asset in embedded) {
        _validateExpectedHash(asset);
        final source = assetSources.sourceFor(asset.id);
        if (source == null) {
          throw ProjectContainerException(
            ProjectContainerFailureCode.missingAssetSource,
            'No byte source was supplied for embedded asset ${asset.id}.',
          );
        }
        final length = await source.length();
        if (length < 0 || length > limits.maxEntryBytes) {
          throw ProjectContainerException(
            ProjectContainerFailureCode.limitExceeded,
            'Asset ${asset.id} exceeds the temporary entry limit.',
          );
        }
        sourceBytes += length;
        final mapping = naming.map(asset);
        if (!limits.allowedCompressionMethods.contains(mapping.compression)) {
          throw ProjectContainerException(
            ProjectContainerFailureCode.unsupportedFeature,
            'The active container limits do not allow ${mapping.compression.name}.',
          );
        }
        mappings[asset.id] = mapping;
        sources[asset.id] = source;
        sourceLengths[asset.id] = length;
      }
      final manifestBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(codec.encode(document))),
      );
      if (manifestBytes.length > limits.maxManifestBytes ||
          sourceBytes + manifestBytes.length > limits.maxUncompressedBytes) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.limitExceeded,
          'Project exceeds the qualified container size policy.',
        );
      }
      final totalBytes = sourceBytes + manifestBytes.length;
      var completedBytes = 0;

      sink = await FileByteSink.create(temporary.path);
      writer = const ZipWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'manifest.json',
          compression: ArchiveCompression.deflate,
        ),
        manifestBytes,
      );
      completedBytes += manifestBytes.length;
      _report(
        onProgress,
        ProjectContainerProgress(
          stage: ProjectContainerStage.writing,
          completedBytes: completedBytes,
          totalBytes: totalBytes,
        ),
      );

      for (final asset in embedded) {
        _throwIfCancelled(cancellation);
        final source = sources[asset.id]!;
        final length = sourceLengths[asset.id]!;
        final digestSink = _SingleDigestSink();
        final hashInput = sha256.startChunkedConversion(digestSink);
        final mapping = mappings[asset.id]!;
        await writer.addStream(
          ArchiveEntrySpec(
            path: mapping.path,
            compression:
                mapping.compression == ProjectContainerCompressionMethod.store
                ? ArchiveCompression.stored
                : ArchiveCompression.deflate,
          ),
          _guardedHashingStream(
            source.openRead(),
            hashInput,
            cancellation,
            onChunk: (count) {
              completedBytes += count;
              _report(
                onProgress,
                ProjectContainerProgress(
                  stage: ProjectContainerStage.writing,
                  completedBytes: completedBytes,
                  totalBytes: totalBytes,
                  assetId: asset.id,
                ),
              );
            },
          ),
          size: length,
        );
        final actual = 'sha256:${digestSink.single}';
        if (actual != asset.contentHash) {
          throw ProjectContainerException(
            ProjectContainerFailureCode.contentMismatch,
            'Asset ${asset.id} changed while the project was being saved.',
          );
        }
      }
      await writer.close();
      writer = null;
      await sink.close();
      sink = null;

      _report(
        onProgress,
        ProjectContainerProgress(
          stage: ProjectContainerStage.verifying,
          completedBytes: 0,
          totalBytes: totalBytes,
        ),
      );
      final verified = await _openValidated(
        temporary,
        cancellation: cancellation,
        onProgress: onProgress,
        progressStage: ProjectContainerStage.verifying,
      );
      await verified.close();
      _throwIfCancelled(cancellation);
      _report(
        onProgress,
        ProjectContainerProgress(
          stage: ProjectContainerStage.replacing,
          completedBytes: totalBytes,
          totalBytes: totalBytes,
        ),
      );
      _throwIfCancelled(cancellation);
      await atomicReplacer.replace(temporary: temporary, destination: target);
    } on ProjectContainerException {
      rethrow;
    } on ProjectDocumentValidationException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidDocument,
        error.toString(),
        error,
      );
    } on FileSystemException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.storageFailure,
        'Project container storage failed.',
        error,
      );
    } on ArchiveException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'ZIP writer rejected the project content.',
        error,
      );
    } catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.storageFailure,
        'An asset source failed while the project was being saved.',
        error,
      );
    } finally {
      await _closeWriter(writer);
      await _closeSink(sink);
      try {
        if (await temporary.exists()) await temporary.delete();
      } finally {
        await scope?.finish(temporary);
      }
    }
  }

  @override
  Future<ProjectContainerSession> open(
    ProjectContainerLocation source, {
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async {
    try {
      return await _openValidated(
        File(source.path),
        cancellation: cancellation,
        onProgress: onProgress,
        progressStage: ProjectContainerStage.opening,
      );
    } on ProjectContainerException {
      rethrow;
    } on ProjectDocumentValidationException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidDocument,
        error.toString(),
        error,
      );
    } on FileSystemException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.storageFailure,
        'Project container could not be opened.',
        error,
      );
    } on ArchiveException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'Project ZIP is corrupt or unsupported.',
        error,
      );
    } on FormatException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'Project manifest is invalid.',
        error,
      );
    } catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'Project container validation failed.',
        error,
      );
    }
  }

  Future<_KoniProjectContainerSession> _openValidated(
    File file, {
    required ProjectContainerCancellation cancellation,
    required ProjectContainerStage progressStage,
    ProjectContainerProgressCallback? onProgress,
  }) async {
    _throwIfCancelled(cancellation);
    final source = await FileByteSource.open(file.path);
    ArchiveReader? reader;
    try {
      final rawEntries = await RawZipEntryScanner(
        limits: limits,
      ).scanSource(source);
      final manifestRecords = rawEntries
          .where((entry) => entry.path == 'manifest.json')
          .toList();
      if (manifestRecords.length != 1 ||
          manifestRecords.single.uncompressedBytes > limits.maxManifestBytes) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.invalidContainer,
          'Project must contain exactly one bounded manifest.json.',
        );
      }
      reader = await const ZipFormat().openReader(
        source,
        ArchiveReadOptions(
          maxEntrySize: limits.maxEntryBytes,
          maxEntryCount: limits.maxEntryCount,
        ),
      );
      if (reader.entries.length != rawEntries.length ||
          reader.entries.any(
            (entry) =>
                entry.type != ArchiveEntryType.file ||
                entry.pathEscapedRoot ||
                entry.isEncrypted ||
                !_allowsCompression(entry.compression),
          )) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.unsupportedFeature,
          'Project contains non-file, escaped, encrypted, or unsupported entries.',
        );
      }
      final entriesByPath = {
        for (final entry in reader.entries) entry.path: entry,
      };
      final manifestEntry = entriesByPath['manifest.json'];
      if (manifestEntry == null) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.invalidContainer,
          'Project manifest is missing.',
        );
      }
      final manifestBytes = await _readBounded(
        reader.openRead(manifestEntry),
        limits.maxManifestBytes,
        cancellation,
      );
      final decodedJson = jsonDecode(utf8.decode(manifestBytes));
      if (decodedJson is! Map) {
        throw const FormatException('Manifest root must be an object.');
      }
      final document = codec.decode(
        decodedJson.map((key, value) => MapEntry(key.toString(), value)),
      );
      documentValidator.validate(document).throwIfInvalid();
      final expectedPaths = <String>{'manifest.json'};
      final assetsByPath = <String, ProjectAsset>{};
      for (final asset in document.assets.where(
        (asset) => asset.storagePolicy == ProjectAssetStoragePolicy.embedded,
      )) {
        _validateExpectedHash(asset);
        final path = naming.map(asset).path;
        expectedPaths.add(path);
        assetsByPath[path] = asset;
      }
      final actualPaths = rawEntries.map((entry) => entry.path).toSet();
      if (actualPaths.length != rawEntries.length ||
          actualPaths.length != expectedPaths.length ||
          !actualPaths.containsAll(expectedPaths) ||
          !expectedPaths.containsAll(actualPaths)) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.invalidContainer,
          'Manifest membership does not match the ZIP entries.',
        );
      }

      final totalBytes = rawEntries.fold<int>(
        0,
        (total, entry) => total + entry.uncompressedBytes,
      );
      _report(
        onProgress,
        ProjectContainerProgress(
          stage: progressStage,
          completedBytes: 0,
          totalBytes: totalBytes,
        ),
      );
      var completed = manifestBytes.length;
      for (final mapping in assetsByPath.entries) {
        _throwIfCancelled(cancellation);
        final digest = await _hashStream(
          reader.openRead(entriesByPath[mapping.key]!),
          cancellation,
          onChunk: (count) {
            completed += count;
            _report(
              onProgress,
              ProjectContainerProgress(
                stage: progressStage,
                completedBytes: completed,
                totalBytes: totalBytes,
                assetId: mapping.value.id,
              ),
            );
          },
        );
        if ('sha256:$digest' != mapping.value.contentHash) {
          throw ProjectContainerException(
            ProjectContainerFailureCode.contentMismatch,
            'Embedded asset ${mapping.value.id} failed SHA-256 validation.',
          );
        }
      }
      return _KoniProjectContainerSession(
        document: document,
        source: source,
        reader: reader,
        entriesByAssetId: {
          for (final item in assetsByPath.entries)
            item.value.id: entriesByPath[item.key]!,
        },
      );
    } catch (_) {
      try {
        await reader?.close();
      } finally {
        await source.close();
      }
      rethrow;
    }
  }

  @override
  Future<int> cleanupStaleTemporaryFiles(
    ProjectContainerLocation destination,
  ) async {
    final target = File(destination.path);
    final prefix = '${target.uri.pathSegments.last}.tmp.';
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    if (!await target.parent.exists()) return 0;
    var removed = 0;
    await for (final entity in target.parent.list(followLinks: false)) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith(prefix) &&
          (await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  void _validateExpectedHash(ProjectAsset asset) {
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(asset.contentHash)) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidDocument,
        'Asset ${asset.id} requires a canonical SHA-256 content hash.',
      );
    }
  }

  bool _allowsCompression(ArchiveCompression compression) =>
      switch (compression) {
        ArchiveCompression.stored => limits.allowedCompressionMethods.contains(
          ProjectContainerCompressionMethod.store,
        ),
        ArchiveCompression.deflate => limits.allowedCompressionMethods.contains(
          ProjectContainerCompressionMethod.deflate,
        ),
        _ => false,
      };

  void _throwIfCancelled(ProjectContainerCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const ProjectContainerException(
        ProjectContainerFailureCode.cancelled,
        'Project container operation was cancelled.',
      );
    }
  }

  void _report(
    ProjectContainerProgressCallback? callback,
    ProjectContainerProgress progress,
  ) {
    try {
      callback?.call(progress);
    } catch (_) {
      // Progress is observational and must never compromise storage integrity.
    }
  }

  Stream<Uint8List> _guardedHashingStream(
    Stream<Uint8List> source,
    ByteConversionSink digest,
    ProjectContainerCancellation cancellation, {
    required void Function(int count) onChunk,
  }) async* {
    try {
      await for (final chunk in source) {
        _throwIfCancelled(cancellation);
        digest.add(chunk);
        onChunk(chunk.length);
        yield chunk;
      }
    } finally {
      digest.close();
    }
  }

  Future<String> _hashStream(
    Stream<Uint8List> stream,
    ProjectContainerCancellation cancellation, {
    required void Function(int count) onChunk,
  }) async {
    final output = _SingleDigestSink();
    final input = sha256.startChunkedConversion(output);
    try {
      await for (final chunk in stream) {
        _throwIfCancelled(cancellation);
        input.add(chunk);
        onChunk(chunk.length);
      }
    } finally {
      input.close();
    }
    return output.single.toString();
  }

  Future<Uint8List> _readBounded(
    Stream<Uint8List> stream,
    int maximumBytes,
    ProjectContainerCancellation cancellation,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      _throwIfCancelled(cancellation);
      if (builder.length + chunk.length > maximumBytes) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.limitExceeded,
          'Manifest exceeds its maximum decoded size.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _closeWriter(ArchiveWriter? writer) async {
    try {
      await writer?.close();
    } catch (_) {}
  }

  Future<void> _closeSink(FileByteSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {}
  }
}

final class _KoniProjectContainerSession implements ProjectContainerSession {
  _KoniProjectContainerSession({
    required this.document,
    required this._source,
    required this._reader,
    required Map<ProjectAssetId, ArchiveEntry> entriesByAssetId,
  }) : _entriesByAssetId = Map.unmodifiable(entriesByAssetId);

  @override
  final ProjectDocument document;
  final FileByteSource _source;
  final ArchiveReader _reader;
  final Map<ProjectAssetId, ArchiveEntry> _entriesByAssetId;
  var _closed = false;

  @override
  Stream<Uint8List> openAsset(ProjectAssetId assetId) async* {
    if (_closed) {
      throw const ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'Project container session is closed.',
      );
    }
    final entry = _entriesByAssetId[assetId];
    if (entry == null) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'No embedded asset exists for $assetId.',
      );
    }
    try {
      yield* _reader.openRead(entry);
    } on ArchiveException catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        'Embedded asset $assetId could not be read.',
        error,
      );
    } catch (error) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.storageFailure,
        'Embedded asset $assetId could not be streamed.',
        error,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _reader.close();
    await _source.close();
  }
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get single {
    final digest = _digest;
    if (digest == null) throw StateError('SHA-256 conversion did not finish.');
    return digest;
  }

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
