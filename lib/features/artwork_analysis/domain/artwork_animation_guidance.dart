enum ArtworkAnimationGuidance {
  unknown,
  flexible,
  autoPathRecommended,
  autoRevealRecommended;

  bool get blocksAutoPath => this == autoRevealRecommended;
}
