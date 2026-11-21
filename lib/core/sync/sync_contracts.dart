import 'dart:io';

export 'sync_identity.dart';

abstract interface class SyncConsentProvider {
  Future<bool> isCloudSyncEnabled(String uid);
}

final class CloudMediaAsset {
  const CloudMediaAsset({
    required this.id,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
  });

  final String id;
  final String sha256;
  final int byteLength;
  final String mediaType;
}

final class CloudAssetReceipt {
  const CloudAssetReceipt({
    required this.storagePath,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
  });

  final String storagePath;
  final String sha256;
  final int byteLength;
  final String mediaType;
}

final class CloudMaterialMetadata {
  const CloudMaterialMetadata({
    required this.materialId,
    required this.title,
    required this.assetId,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
    required this.storagePath,
    required this.opId,
    required this.payloadHash,
  });

  final String materialId;
  final String title;
  final String assetId;
  final String sha256;
  final int byteLength;
  final String mediaType;
  final String storagePath;
  final String opId;
  final String payloadHash;

  Map<String, Object> toFirestoreDocument(String uid) => {
    'schemaVersion': 1,
    'ownerId': uid,
    'materialId': materialId,
    'title': title,
    'audioAssetId': assetId,
    'assetSha256': sha256,
    'byteLength': byteLength,
    'mediaType': mediaType,
    'storagePath': storagePath,
    'opId': opId,
    'payloadHash': payloadHash,
    'status': 'cloudReady',
  };
}

final class CloudAssetMetadata {
  const CloudAssetMetadata({
    required this.assetId,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
    required this.storagePath,
    required this.opId,
    required this.payloadHash,
  });

  final String assetId;
  final String sha256;
  final int byteLength;
  final String mediaType;
  final String storagePath;
  final String opId;
  final String payloadHash;

  Map<String, Object> toFirestoreDocument(String uid) => {
    'schemaVersion': 1,
    'ownerId': uid,
    'assetId': assetId,
    'sha256': sha256,
    'byteLength': byteLength,
    'mediaType': mediaType,
    'storagePath': storagePath,
    'opId': opId,
    'payloadHash': payloadHash,
  };

  Map<String, String> toStorageCustomMetadata(String uid) => {
    'ownerId': uid,
    'assetId': assetId,
    'sha256': sha256,
    'opId': opId,
    'payloadHash': payloadHash,
  };
}

abstract interface class CloudSyncTransport {
  /// Uploads idempotently to the caller's authenticated UID namespace.
  Future<CloudAssetReceipt> uploadAsset({
    required String uid,
    required CloudMediaAsset asset,
    required File localFile,
    required String opId,
    required String payloadHash,
  });

  Future<void> publishAsset({
    required String uid,
    required CloudAssetMetadata metadata,
  });

  /// Publishes only after [receipt] has been verified against local metadata.
  Future<void> publishMaterial({
    required String uid,
    required CloudMaterialMetadata metadata,
  });
}

enum SyncFailureKind {
  transient,
  unauthenticated,
  permissionDenied,
  invalidData,
}

final class SyncFailure implements Exception {
  const SyncFailure(this.kind, this.code);

  final SyncFailureKind kind;
  final String code;

  @override
  String toString() => 'SyncFailure($kind, $code)';
}

abstract interface class SyncOutbox {
  Future<SyncOperation?> claimNext(String ownerId, DateTime now);
  Future<void> complete(String ownerId, String opId, DateTime now);
  Future<void> release(String ownerId, String opId, DateTime now);
  Future<void> deferForAuthentication(
    String ownerId,
    String opId,
    DateTime now,
  );
  Future<void> fail({
    required String ownerId,
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime? retryAt,
  });
  Future<void> resumeAuthenticated(String ownerId, DateTime now);
  Future<void> retryNeedsAttention(String ownerId, String opId, DateTime now);
}

enum SyncOperationKind { material, subtitle }

final class SyncOperation {
  const SyncOperation({
    required this.ownerId,
    required this.opId,
    required this.entityId,
    required this.payloadJson,
    required this.payloadHash,
    required this.attempts,
    this.kind = SyncOperationKind.material,
  });

  final String ownerId;
  final String opId;
  final String entityId;
  final String payloadJson;
  final String payloadHash;
  final int attempts;
  final SyncOperationKind kind;
}
