import 'package:handdraw_project_container_benchmark/archive_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = ArchiveSecurityPolicy();
  const manifest = ArchiveEntryDescriptor(
    path: 'manifest.json',
    compressedBytes: 100,
    uncompressedBytes: 100,
  );

  test('entry names derive only from typed metadata and persistent ID', () {
    const naming = ArchiveEntryNamingPolicy();
    expect(
      naming.assetEntry(
        assetId: 'asset_abcd',
        kind: BenchmarkAssetKind.artwork,
        validatedMediaType: 'image/svg+xml',
      ),
      'assets/artwork/asset_abcd.svg',
    );
    expect(
      () => naming.assetEntry(
        assetId: '../user name',
        kind: BenchmarkAssetKind.audio,
        validatedMediaType: 'audio/mp4',
      ),
      throwsArgumentError,
    );
    expect(
      () => naming.assetEntry(
        assetId: 'asset_a',
        kind: BenchmarkAssetKind.other,
        validatedMediaType: 'application/x-unknown',
      ),
      throwsA(isA<UnsupportedMediaTypeException>()),
    );
  });

  test('accepts one safe manifest and safe asset entries', () {
    expect(
      () => policy.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/audio/asset_a.m4a',
          compressedBytes: 1000,
          uncompressedBytes: 1000,
        ),
      ]),
      returnsNormally,
    );
  });

  for (final path in const [
    '../escape',
    'assets/../escape',
    '/absolute',
    r'C:\device\file',
    r'assets\file',
    'assets//file',
    'assets/control\u0001.svg',
    'assets/delete\u007f.svg',
  ]) {
    test('rejects unsafe entry $path', () {
      expect(
        () => policy.validate([
          manifest,
          const ArchiveEntryDescriptor(
            path: 'assets/safe.bin',
            compressedBytes: 1,
            uncompressedBytes: 1,
          ),
          ArchiveEntryDescriptor(
            path: path,
            compressedBytes: 1,
            uncompressedBytes: 1,
          ),
        ]),
        throwsA(
          isA<ArchiveSecurityException>().having(
            (error) => error.issue,
            'issue',
            ArchiveSecurityIssue.unsafePath,
          ),
        ),
      );
    });
  }

  test('rejects duplicate entries case-insensitively', () {
    expect(
      () => policy.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/A.bin',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
        ArchiveEntryDescriptor(
          path: 'assets/a.bin',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
      ]),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.duplicateEntry,
        ),
      ),
    );
  });

  test('reports a duplicate manifest independently from other collisions', () {
    expect(
      () => policy.validate(const [manifest, manifest]),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.duplicateManifest,
        ),
      ),
    );
  });

  test('reports external content hash mismatches as a typed failure', () {
    const error = ExternalAssetContentMismatch(
      assetId: 'asset_a',
      expectedHash: 'sha256:expected',
      actualHash: 'sha256:actual',
    );
    expect(error.assetId, 'asset_a');
    expect(error.toString(), contains('sha256:expected'));
  });

  test('manifest membership is closed in both directions', () {
    const membership = ArchiveManifestMembershipPolicy();
    expect(
      () => membership.validate(
        archivePaths: const ['manifest.json', 'assets/a.svg'],
        declaredAssetPaths: const ['assets/a.svg'],
      ),
      returnsNormally,
    );
    expect(
      () => membership.validate(
        archivePaths: const ['manifest.json', 'assets/extra.svg'],
        declaredAssetPaths: const <String>[],
      ),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.unmanifestedEntry,
        ),
      ),
    );
    expect(
      () => membership.validate(
        archivePaths: const ['manifest.json'],
        declaredAssetPaths: const ['assets/missing.svg'],
      ),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.missingManifestEntry,
        ),
      ),
    );
  });

  test('rejects missing manifest, symlinks, bombs, and entry floods', () {
    expect(
      () => policy.validate(const []),
      throwsA(isA<ArchiveSecurityException>()),
    );
    expect(
      () => policy.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/link',
          compressedBytes: 1,
          uncompressedBytes: 1,
          isSymbolicLink: true,
        ),
      ]),
      throwsA(isA<ArchiveSecurityException>()),
    );
    expect(
      () => policy.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/bomb.svg',
          compressedBytes: 1,
          uncompressedBytes: 1000,
        ),
      ]),
      throwsA(isA<ArchiveSecurityException>()),
    );
    const tinyLimit = ArchiveSecurityPolicy(
      limits: ArchiveSecurityLimits(maximumEntries: 1),
    );
    expect(
      () => tinyLimit.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/file.bin',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
      ]),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.entryLimit,
        ),
      ),
    );
  });

  test('enforces per-entry and aggregate uncompressed limits', () {
    const constrained = ArchiveSecurityPolicy(
      limits: ArchiveSecurityLimits(
        maximumEntryBytes: 100,
        maximumTotalBytes: 150,
      ),
    );
    expect(
      () => constrained.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/too-large.bin',
          compressedBytes: 101,
          uncompressedBytes: 101,
        ),
      ]),
      throwsA(isA<ArchiveSecurityException>()),
    );
    expect(
      () => constrained.validate(const [
        manifest,
        ArchiveEntryDescriptor(
          path: 'assets/pushes-total.bin',
          compressedBytes: 51,
          uncompressedBytes: 51,
        ),
      ]),
      throwsA(
        isA<ArchiveSecurityException>().having(
          (error) => error.issue,
          'issue',
          ArchiveSecurityIssue.totalSizeLimit,
        ),
      ),
    );
  });
}
