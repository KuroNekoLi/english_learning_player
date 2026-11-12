import 'dart:io';

import 'package:english_learning_player/core/sync/sync_contracts.dart';

final class FakeSyncIdentityProvider implements SyncIdentityProvider {
  FakeSyncIdentityProvider([this.identity]);

  SyncIdentity? identity;

  @override
  Future<SyncIdentity?> currentIdentity() async => identity;
}

final class FakeSyncConsentProvider implements SyncConsentProvider {
  FakeSyncConsentProvider({this.enabled = true});

  bool enabled;

  @override
  Future<bool> isCloudSyncEnabled(String uid) async => enabled;
}

final class FakeCloudSyncTransport implements CloudSyncTransport {
  int uploadCount = 0;
  int assetMetadataCount = 0;
  int materialMetadataCount = 0;
  String? lastOpId;
  String? lastPayloadHash;
  CloudAssetMetadata? lastAssetMetadata;
  CloudMaterialMetadata? lastMaterialMetadata;
  SyncFailure? uploadFailure;
  SyncFailure? assetMetadataFailure;
  SyncFailure? materialMetadataFailure;
  Future<void> Function()? afterUpload;

  @override
  Future<CloudAssetReceipt> uploadAsset({
    required String uid,
    required CloudMediaAsset asset,
    required File localFile,
    required String opId,
    required String payloadHash,
  }) async {
    uploadCount++;
    lastOpId = opId;
    lastPayloadHash = payloadHash;
    if (uploadFailure case final failure?) throw failure;
    await afterUpload?.call();
    return CloudAssetReceipt(
      storagePath: 'users/$uid/assets/${asset.id}/${asset.sha256}',
      sha256: asset.sha256,
      byteLength: asset.byteLength,
      mediaType: asset.mediaType,
    );
  }

  @override
  Future<void> publishAsset({
    required String uid,
    required CloudAssetMetadata metadata,
  }) async {
    assetMetadataCount++;
    lastAssetMetadata = metadata;
    if (assetMetadataFailure case final failure?) throw failure;
  }

  @override
  Future<void> publishMaterial({
    required String uid,
    required CloudMaterialMetadata metadata,
  }) async {
    materialMetadataCount++;
    lastMaterialMetadata = metadata;
    if (materialMetadataFailure case final failure?) throw failure;
  }
}
