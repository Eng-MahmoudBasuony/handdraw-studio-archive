enum ProjectContainerCompressionMethod {
  store(0),
  deflate(8);

  const ProjectContainerCompressionMethod(this.zipCode);

  final int zipCode;
}

/// The single production safety policy shared by container reads and writes.
///
/// Archive bytes, aggregate uncompressed bytes, and per-entry bytes are
/// intentionally independent limits even while their provisional values are
/// all below 4 GiB.
final class ProjectContainerLimits {
  const ProjectContainerLimits({
    this.maxArchiveBytes = 0xffffffff,
    this.maxUncompressedBytes = 0xffffffff,
    this.maxEntryBytes = 0xffffffff,
    this.maxEntryCount = 10000,
    this.maxCompressionRatio = 200,
    this.maxManifestBytes = 16 * 1024 * 1024,
    this.allowedCompressionMethods = const {
      ProjectContainerCompressionMethod.store,
      ProjectContainerCompressionMethod.deflate,
    },
  });

  final int maxArchiveBytes;
  final int maxUncompressedBytes;
  final int maxEntryBytes;
  final int maxEntryCount;
  final double maxCompressionRatio;
  final int maxManifestBytes;
  final Set<ProjectContainerCompressionMethod> allowedCompressionMethods;

  bool allowsCompressionCode(int code) =>
      allowedCompressionMethods.any((method) => method.zipCode == code);
}
