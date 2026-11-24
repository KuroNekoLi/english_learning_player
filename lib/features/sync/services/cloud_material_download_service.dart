import '../../../core/db/account_scope.dart';
import '../../../core/files/media_store.dart';
import '../../../core/sync/sync_contracts.dart';
import '../../library/domain/audio_import_source.dart';
import '../../library/material_repository.dart';

abstract interface class CloudMaterialDownloadTransport {
  /// The adapter must authenticate the caller and read only this UID's object.
  Stream<List<int>> readAudio({
    required String uid,
    required String storagePath,
  });
}

final class CloudMaterialDownloadService {
  const CloudMaterialDownloadService({
    required this._scope,
    this.remoteOwnerUid,
    required SyncIdentityProvider identityProvider,
    required SyncConsentProvider consentProvider,
    required this._transport,
    required this._repository,
    required this._mediaStore,
  }) : _identity = identityProvider,
       _consent = consentProvider;

  final AccountScope _scope;
  final String? remoteOwnerUid;
  final SyncIdentityProvider _identity;
  final SyncConsentProvider _consent;
  final CloudMaterialDownloadTransport _transport;
  final CloudMaterialCacheRepository _repository;
  final MediaStore _mediaStore;

  String get _ownerUid => remoteOwnerUid ?? _scope.ownerId;

  Future<LearningMaterial> download(
    CloudMaterialMetadata metadata, {
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
    void Function()? onAudioCached,
  }) async {
    final uid = _ownerUid;
    final extension = switch (metadata.mediaType) {
      'audio/mpeg' => 'mp3',
      'audio/mp4' => 'm4a',
      _ => throw const SyncFailure(SyncFailureKind.invalidData, 'invalid_mime'),
    };
    if (!_segment(uid) ||
        !_segment(metadata.materialId) ||
        !_segment(metadata.assetId) ||
        metadata.byteLength <= 0 ||
        metadata.byteLength > 104857600 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(metadata.sha256) ||
        metadata.storagePath !=
            'users/$uid/assets/${metadata.assetId}/${metadata.sha256}') {
      throw const SyncFailure(SyncFailureKind.invalidData, 'invalid_metadata');
    }
    await _checkAccess();
    final audio = await _mediaStore.copyAndHash(
      AudioImportSource(
        sourceKey: metadata.materialId,
        name: 'download.$extension',
        openRead: () => _boundedRead(metadata, onProgress),
      ),
      verifyBeforePublish: (audio) async {
        if (audio.sha256 != metadata.sha256 ||
            audio.byteLength != metadata.byteLength ||
            audio.mediaType != metadata.mediaType) {
          throw const SyncFailure(
            SyncFailureKind.invalidData,
            'download_integrity_mismatch',
          );
        }
        await _checkAccess();
      },
    );
    await _checkAccess();
    final material = await _repository.cacheCloudAudio(
      materialId: metadata.materialId,
      title: metadata.title,
      cachedAt: DateTime.now().toUtc(),
      asset: StoredAudioAsset(
        id: metadata.assetId,
        sha256: audio.sha256,
        byteLength: audio.byteLength,
        mediaType: audio.mediaType,
        relativePath: audio.relativePath,
      ),
    );
    onAudioCached?.call();
    return material;
  }

  Stream<List<int>> _boundedRead(
    CloudMaterialMetadata metadata,
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
  ) async* {
    var length = 0;
    onProgress?.call(0, metadata.byteLength);
    await for (final chunk in _transport.readAudio(
      uid: _ownerUid,
      storagePath: metadata.storagePath,
    )) {
      length += chunk.length;
      if (length > metadata.byteLength) {
        throw const SyncFailure(
          SyncFailureKind.invalidData,
          'download_integrity_mismatch',
        );
      }
      onProgress?.call(length, metadata.byteLength);
      yield chunk;
    }
  }

  Future<void> _checkAccess() async {
    final uid = _ownerUid;
    if ((await _identity.currentIdentity())?.uid != uid) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'account_changed',
      );
    }
    if (!await _consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
    if ((await _identity.currentIdentity())?.uid != uid) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'account_changed',
      );
    }
  }

  bool _segment(String value) =>
      value.isNotEmpty && value != '.' && value != '..' && !value.contains('/');
}
