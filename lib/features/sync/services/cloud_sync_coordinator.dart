import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../library/material_repository.dart';
import '../../../core/db/account_database_service.dart';
import '../../../core/db/account_scope.dart';
import '../../../core/sync/sqlite_sync_outbox.dart';
import '../../../core/sync/subtitle_outbox_entry.dart';
import '../../../core/sync/sync_contracts.dart';

enum SyncRunResult {
  idle,
  waitingForConsent,
  waitingForAuthentication,
  uploaded,
  retryScheduled,
  needsAttention,
}

typedef SyncClock = DateTime Function();
typedef SyncRandom = double Function();

final class CloudSyncCoordinator {
  CloudSyncCoordinator({
    required AccountScope scope,
    required SyncIdentityProvider identityProvider,
    required SyncConsentProvider consentProvider,
    required SyncOutbox outbox,
    required MaterialRepository materials,
    required AccountDatabaseService mediaFiles,
    required CloudSyncTransport transport,
    Future<void> Function(String materialId)? publishSubtitles,
    SyncClock? clock,
    SyncRandom? random,
  }) : _scope = scope,
       _identityProvider = identityProvider,
       _consentProvider = consentProvider,
       _outbox = outbox,
       _materials = materials,
       _mediaFiles = mediaFiles,
       _transport = transport,
       _publishSubtitles = publishSubtitles,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random().nextDouble;

  final AccountScope _scope;
  final SyncIdentityProvider _identityProvider;
  final SyncConsentProvider _consentProvider;
  final SyncOutbox _outbox;
  final MaterialRepository _materials;
  final AccountDatabaseService _mediaFiles;
  final CloudSyncTransport _transport;
  final Future<void> Function(String materialId)? _publishSubtitles;
  final SyncClock _clock;
  final SyncRandom _random;

  Future<SyncRunResult> runOne() async {
    final identity = await _identityProvider.currentIdentity();
    if (identity == null) return SyncRunResult.waitingForAuthentication;
    if (identity.uid != _scope.ownerId) {
      throw StateError(
        'Authenticated UID does not match the local account scope.',
      );
    }
    if (!await _consentProvider.isCloudSyncEnabled(identity.uid)) {
      return SyncRunResult.waitingForConsent;
    }
    final now = _clock();
    await _outbox.resumeAuthenticated(identity.uid, now);
    final operation = await _outbox.claimNext(identity.uid, now);
    if (operation == null) return SyncRunResult.idle;

    try {
      if (operation.ownerId != identity.uid) {
        throw StateError(
          'Outbox operation owner does not match authenticated UID.',
        );
      }
      if (operation.kind == SyncOperationKind.subtitle) {
        return await _runSubtitleOperation(operation);
      }
      final payload = _parsePayload(operation);
      final asset = await _materials.audioAssetForMaterial(operation.entityId);
      if (asset == null || asset.id != payload.assetId) {
        throw const SyncFailure(
          SyncFailureKind.invalidData,
          'local_asset_missing',
        );
      }
      if (asset.sha256 != payload.sha256 ||
          asset.byteLength != payload.byteLength ||
          asset.mediaType != payload.mediaType) {
        throw const SyncFailure(
          SyncFailureKind.invalidData,
          'local_metadata_mismatch',
        );
      }
      final file = _mediaFiles.resolveMediaFile(_scope, asset.relativePath);
      await _verifyLocalFile(file, asset);
      if (!await _stillSameIdentity(identity.uid)) {
        await _outbox.deferForAuthentication(
          identity.uid,
          operation.opId,
          _clock(),
        );
        return SyncRunResult.waitingForAuthentication;
      }

      final receipt = await _transport.uploadAsset(
        uid: identity.uid,
        asset: CloudMediaAsset(
          id: asset.id,
          sha256: asset.sha256,
          byteLength: asset.byteLength,
          mediaType: asset.mediaType,
        ),
        localFile: file,
        opId: operation.opId,
        payloadHash: operation.payloadHash,
      );
      _verifyReceipt(receipt, asset);
      if (!await _stillSameIdentity(identity.uid)) {
        await _outbox.deferForAuthentication(
          identity.uid,
          operation.opId,
          _clock(),
        );
        return SyncRunResult.waitingForAuthentication;
      }
      final metadata = CloudMaterialMetadata(
        materialId: payload.materialId,
        title: payload.title,
        assetId: asset.id,
        sha256: asset.sha256,
        byteLength: asset.byteLength,
        mediaType: asset.mediaType,
        storagePath: receipt.storagePath,
        opId: operation.opId,
        payloadHash: operation.payloadHash,
      );
      await _transport.publishAsset(
        uid: identity.uid,
        metadata: CloudAssetMetadata(
          assetId: asset.id,
          sha256: asset.sha256,
          byteLength: asset.byteLength,
          mediaType: asset.mediaType,
          storagePath: receipt.storagePath,
          opId: operation.opId,
          payloadHash: operation.payloadHash,
        ),
      );
      if (!await _stillSameIdentity(identity.uid)) {
        await _outbox.deferForAuthentication(
          identity.uid,
          operation.opId,
          _clock(),
        );
        return SyncRunResult.waitingForAuthentication;
      }
      await _transport.publishMaterial(uid: identity.uid, metadata: metadata);
      if (!await _stillSameIdentity(identity.uid)) {
        await _outbox.deferForAuthentication(
          identity.uid,
          operation.opId,
          _clock(),
        );
        return SyncRunResult.waitingForAuthentication;
      }
      await _outbox.complete(identity.uid, operation.opId, _clock());
      return SyncRunResult.uploaded;
    } on SyncFailure catch (failure) {
      if (operation.kind == SyncOperationKind.subtitle &&
          failure.code == 'consent_required') {
        await _outbox.release(identity.uid, operation.opId, _clock());
        return SyncRunResult.waitingForConsent;
      }
      if (failure.kind == SyncFailureKind.unauthenticated) {
        await _outbox.deferForAuthentication(
          identity.uid,
          operation.opId,
          _clock(),
        );
        return SyncRunResult.waitingForAuthentication;
      }
      final retryable = failure.kind == SyncFailureKind.transient;
      final retryAt = retryable
          ? nextRetryAt(_clock(), operation.attempts + 1, _random())
          : null;
      await _outbox.fail(
        ownerId: identity.uid,
        opId: operation.opId,
        code: failure.code,
        retryable: retryable,
        now: _clock(),
        retryAt: retryAt,
      );
      return retryable && operation.attempts + 1 < 8
          ? SyncRunResult.retryScheduled
          : SyncRunResult.needsAttention;
    } on FileSystemException {
      await _outbox.fail(
        ownerId: identity.uid,
        opId: operation.opId,
        code: 'local_file_unavailable',
        retryable: true,
        now: _clock(),
        retryAt: nextRetryAt(_clock(), operation.attempts + 1, _random()),
      );
      return operation.attempts + 1 >= 8
          ? SyncRunResult.needsAttention
          : SyncRunResult.retryScheduled;
    }
  }

  Future<SyncRunResult> _runSubtitleOperation(SyncOperation operation) async {
    final uid = operation.ownerId;
    if (operation.payloadJson !=
            SubtitleOutboxEntry.payload(operation.entityId) ||
        SqliteSyncOutbox.payloadHash(operation.payloadJson) !=
            operation.payloadHash) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_outbox_payload',
      );
    }
    final publish = _publishSubtitles;
    if (publish == null) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'subtitle_publisher_missing',
      );
    }
    if (!await _stillSameIdentity(uid)) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'unauthenticated',
      );
    }
    if (!await _consentProvider.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
    await publish(operation.entityId);
    if (!await _stillSameIdentity(uid)) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'unauthenticated',
      );
    }
    if (!await _consentProvider.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
    await _outbox.complete(uid, operation.opId, _clock());
    return SyncRunResult.uploaded;
  }

  void _verifyReceipt(CloudAssetReceipt receipt, StoredAudioAsset asset) {
    final expectedPath =
        'users/${_scope.ownerId}/assets/${asset.id}/${asset.sha256}';
    if (receipt.storagePath != expectedPath ||
        receipt.sha256 != asset.sha256 ||
        receipt.byteLength != asset.byteLength ||
        receipt.mediaType != asset.mediaType) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'cloud_asset_integrity_mismatch',
      );
    }
  }

  Future<void> _verifyLocalFile(File file, StoredAudioAsset asset) async {
    if (!await file.exists() || await file.length() != asset.byteLength) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'local_asset_integrity_mismatch',
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != asset.sha256) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'local_asset_integrity_mismatch',
      );
    }
  }

  Future<bool> _stillSameIdentity(String uid) async =>
      (await _identityProvider.currentIdentity())?.uid == uid;

  _MaterialPayload _parsePayload(SyncOperation operation) {
    if (SqliteSyncOutbox.payloadHash(operation.payloadJson) !=
        operation.payloadHash) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'outbox_payload_hash_mismatch',
      );
    }
    try {
      final json = jsonDecode(operation.payloadJson) as Map<String, dynamic>;
      if (json['schemaVersion'] != 1 ||
          json['materialId'] != operation.entityId) {
        throw const FormatException();
      }
      return _MaterialPayload(
        materialId: json['materialId'] as String,
        title: json['title'] as String,
        assetId: json['assetId'] as String,
        sha256: json['sha256'] as String,
        byteLength: json['byteLength'] as int,
        mediaType: json['mediaType'] as String,
      );
    } on Object {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_outbox_payload',
      );
    }
  }
}

DateTime nextRetryAt(DateTime now, int attempt, double randomValue) {
  if (attempt < 1 || randomValue < 0 || randomValue > 1) {
    throw ArgumentError('Retry attempt and random value are out of range.');
  }
  final seconds = min(60, 1 << min(attempt - 1, 6));
  final delayMs = (seconds * 500 + seconds * 500 * randomValue).round();
  return now.add(Duration(milliseconds: delayMs));
}

final class _MaterialPayload {
  const _MaterialPayload({
    required this.materialId,
    required this.title,
    required this.assetId,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
  });

  final String materialId;
  final String title;
  final String assetId;
  final String sha256;
  final int byteLength;
  final String mediaType;
}
