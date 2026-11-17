import '../subtitles/domain/subtitle_models.dart';

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

  Future<StoredAudioAsset?> audioAssetForMaterial(String materialId);

  Future<InsertMaterialResult> insertAudio({
    required StoredAudioAsset asset,
    required String sourceKey,
    required String title,
    required String materialId,
    required DateTime createdAt,
  });

  Future<SubtitleTrack> saveSubtitleTrack(
    SubtitleTrack track, {
    required bool manual,
  });

  Future<List<SubtitleTrack>> listSubtitleTracks(String materialId);
}

/// Local source catalog used to make full folder scans idempotent. Paths stay
/// inside the account's local database and are never part of cloud metadata.
abstract interface class FolderReconciliationRepository {
  Future<List<FolderSourceRecord>> listFolderSources(String bindingId);

  Future<void> finishFolderScan({
    required String bindingId,
    required Set<String> inventoryPaths,
  });

  Future<void> saveFolderSource({
    required String bindingId,
    required String relativePath,
    required String materialId,
    required String contentSha256,
  });

  Future<void> addToFolderPlaylist({
    required String bindingId,
    required String materialId,
    required String title,
  });
}

final class FolderSourceRecord {
  const FolderSourceRecord({
    required this.relativePath,
    required this.materialId,
    required this.contentSha256,
    required this.present,
  });

  final String relativePath;
  final String materialId;
  final String contentSha256;
  final bool present;
}

final class StoredAudioAsset {
  const StoredAudioAsset({
    required this.id,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
    required this.relativePath,
  });

  final String id;
  final String sha256;
  final int byteLength;
  final String mediaType;
  final String relativePath;
}

final class InsertMaterialResult {
  const InsertMaterialResult({
    required this.material,
    required this.wasDuplicate,
  });

  final LearningMaterial material;
  final bool wasDuplicate;
}
