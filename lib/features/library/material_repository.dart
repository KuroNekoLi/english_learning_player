enum MaterialStatus {
  importing,
  localReady,
  uploading,
  cloudReady,
  error,
  archived,
}

final class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.audioAssetId,
    required this.status,
    required this.createdAt,
    this.durationMs,
  });

  final String id;
  final String ownerId;
  final String title;
  final String audioAssetId;
  final MaterialStatus status;
  final DateTime createdAt;
  final int? durationMs;
}

/// Local read boundary. Each instance is scoped to one local profile or UID.
abstract interface class MaterialRepository {
  Future<List<LearningMaterial>> listMaterials();
}
