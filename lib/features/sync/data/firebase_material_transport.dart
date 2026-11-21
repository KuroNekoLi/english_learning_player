import '../../../core/sync/sync_contracts.dart';
import '../../auth/data/firebase_identity_session.dart';
import '../../../core/firebase/firebase_endpoint.dart';
import '../services/cloud_material_download_service.dart';
import 'firebase_documents.dart';
import 'firebase_storage_objects.dart';

final class FirebaseMaterialTransport
    implements CloudSyncTransport, CloudMaterialDownloadTransport {
  FirebaseMaterialTransport(
    FirebaseEndpoint endpoint,
    FirebaseIdentitySession session,
    FirebaseHttp http,
  ) : documents = FirebaseDocuments(endpoint, session, http),
      objects = FirebaseStorageObjects(endpoint, session, http);

  final FirebaseDocuments documents;
  final FirebaseStorageObjects objects;

  @override
  Future<CloudAssetReceipt> uploadAsset({
    required String uid,
    required CloudMediaAsset asset,
    required Stream<List<int>> Function() openRead,
    required String opId,
    required String payloadHash,
  }) => objects.uploadAsset(
    uid: uid,
    asset: asset,
    openRead: openRead,
    opId: opId,
    payloadHash: payloadHash,
  );

  @override
  Future<void> publishAsset({
    required String uid,
    required CloudAssetMetadata metadata,
  }) async {
    final path = ['users', uid, 'mediaAssets', metadata.assetId];
    final record = metadata.toFirestoreDocument(uid);
    final existing = await documents.readDocument(uid, path);
    if (existing != null) {
      // Multiple local materials can reference the same immutable audio asset.
      for (final field in record.keys.where(
        (key) => key != 'opId' && key != 'payloadHash',
      )) {
        if (record[field] != existing[field]) _invalidAsset();
      }
      return;
    }
    try {
      await documents.writeDocument(uid, path, record, createOnly: true);
    } on SyncFailure catch (error) {
      if (error.kind != SyncFailureKind.permissionDenied &&
          error.code != 'firebase_http_409' &&
          error.code != 'firebase_http_400' &&
          error.code != 'firebase_http_412') {
        rethrow;
      }
      final raced = await documents.readDocument(uid, path);
      if (raced == null) rethrow;
      for (final field in record.keys.where(
        (key) => key != 'opId' && key != 'payloadHash',
      )) {
        if (record[field] != raced[field]) _invalidAsset();
      }
    }
  }

  @override
  Future<void> publishMaterial({
    required String uid,
    required CloudMaterialMetadata metadata,
  }) => documents.writeDocument(uid, [
    'users',
    uid,
    'materials',
    metadata.materialId,
  ], metadata.toFirestoreDocument(uid));

  Future<List<CloudMaterialMetadata>> listMaterials(String uid) async {
    final records = await documents.listDocuments(uid, [
      'users',
      uid,
      'materials',
    ]);
    final materials = <CloudMaterialMetadata>[];
    for (final json in records) {
      if (json['ownerId'] != uid ||
          json['status'] != 'cloudReady' ||
          json['schemaVersion'] != 1) {
        continue;
      }
      try {
        materials.add(
          CloudMaterialMetadata(
            materialId: json['materialId'] as String,
            title: json['title'] as String,
            assetId: json['audioAssetId'] as String,
            sha256: json['assetSha256'] as String,
            byteLength: json['byteLength'] as int,
            mediaType: json['mediaType'] as String,
            storagePath: json['storagePath'] as String,
            opId: json['opId'] as String,
            payloadHash: json['payloadHash'] as String,
          ),
        );
      } on TypeError {
        continue;
      }
    }
    return List.unmodifiable(materials);
  }

  @override
  Stream<List<int>> readAudio({
    required String uid,
    required String storagePath,
  }) => objects.readObject(uid, storagePath);

  static Never _invalidAsset() => throw const SyncFailure(
    SyncFailureKind.invalidData,
    'cloud_asset_integrity_mismatch',
  );
}
