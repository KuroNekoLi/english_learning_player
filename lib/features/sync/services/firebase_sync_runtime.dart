import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../library/data/sqlite_material_repository.dart';
import '../../progress/data/sqlite_progress_repository.dart';
import '../../progress/domain/progress_models.dart';
import '../../progress/services/progress_sync_coordinator.dart';
import '../data/firebase_material_transport.dart';
import '../data/firebase_progress_transport.dart';
import '../data/firebase_subtitle_sync.dart';
import 'cloud_material_download_service.dart';
import 'cloud_sync_coordinator.dart';

final class FirebaseSyncRuntime {
  FirebaseSyncRuntime({
    required this.uid,
    required this.hasDueMedia,
    required this.transport,
    required this.coordinator,
    required this.downloader,
    required this.consent,
    required this.repository,
    required this.subtitles,
    required this.progress,
    required this.progressTransport,
    required this.progressCoordinator,
  });

  final String uid;
  final Future<bool> Function(DateTime now) hasDueMedia;
  Future<SyncRunResult>? _mediaPass;
  final FirebaseMaterialTransport transport;
  final CloudSyncCoordinator coordinator;
  final CloudMaterialDownloadService downloader;
  final SyncConsentProvider consent;
  final SqliteMaterialRepository repository;
  final FirebaseSubtitleSync subtitles;
  final SqliteProgressRepository progress;
  final FirebaseProgressTransport? progressTransport;
  final ProgressSyncCoordinator? progressCoordinator;

  Future<List<CloudMaterialMetadata>> refresh() async {
    await _checkConsent();
    final catalog = await transport.listMaterials(uid);
    final local = (await repository.listMaterials())
        .map((item) => item.id)
        .toSet();
    final authored = await repository.uploadedMaterialIds();
    for (final item in catalog.where(
      (item) => local.contains(item.materialId),
    )) {
      if (!authored.contains(item.materialId)) {
        await subtitles.download(item.materialId);
      }
      await _pullProgress(item.materialId);
    }
    return catalog;
  }

  Future<void> download(
    CloudMaterialMetadata metadata, {
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
    void Function()? onAudioCached,
    void Function(CloudDownloadPhase phase)? onPhaseChanged,
  }) async {
    onPhaseChanged?.call(CloudDownloadPhase.audio);
    await downloader.download(
      metadata,
      onProgress: onProgress,
      onAudioCached: () {
        onAudioCached?.call();
        onPhaseChanged?.call(CloudDownloadPhase.subtitles);
      },
    );
    await subtitles.download(metadata.materialId);
    await _pullProgress(metadata.materialId);
  }

  Future<List<ProgressCandidate>> conflicts(String materialId) =>
      progress.unresolvedCandidates(materialId);

  Future<void> resolve(ProgressCandidate candidate, bool useCandidate) async {
    final materialId = candidate.checkpoint.stream.materialId;
    final local = await progress.canonical(materialId);
    if (local == null) return;
    await progress.resolveCandidate(
      candidateId: candidate.id,
      observedCanonicalRevision: local.revision,
      useCandidatePosition: useCandidate,
      resolutionStream: (
        ownerId: uid,
        materialId: materialId,
        deviceId: await progress.deviceId(),
        sessionId: const Uuid().v4(),
      ),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _pullProgress(String materialId) async {
    final source = progressTransport;
    if (source == null) return;
    await _checkConsent();
    final progressSnapshot = await source.canonical(uid, materialId);
    await _checkConsent();
    if (progressSnapshot != null) {
      await progress.mergeRemoteCanonical(
        checkpoint: progressSnapshot.checkpoint,
        revision: progressSnapshot.revision,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _checkConsent() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
  }

  /// Bound a foreground sync pass and stop at a retry or authorization boundary.
  Future<SyncRunResult> sync({bool mediaOnly = false}) async {
    final status = await (_mediaPass ??= _runMediaPass());
    return !mediaOnly && status == SyncRunResult.idle
        ? _syncProgress()
        : status;
  }

  Future<SyncRunResult> _runMediaPass() async {
    try {
      return await _syncMedia();
    } finally {
      _mediaPass = null;
    }
  }

  Future<SyncRunResult> _syncMedia() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      return SyncRunResult.waitingForConsent;
    }
    // Check the catalog before uploading any audio to Storage. A project
    // configured for sign-in and Storage may still lack the Firestore database.
    await transport.documents.checkCollectionAccess(uid, [
      'users',
      uid,
      'materials',
    ]);
    for (var i = 0; i < 20; i++) {
      final status = await coordinator.runOne();
      if (status != SyncRunResult.uploaded) return status;
    }
    return SyncRunResult.uploaded;
  }

  Future<SyncRunResult> _syncProgress() async {
    final runner = progressCoordinator;
    if (runner == null) return SyncRunResult.idle;
    for (var i = 0; i < 20; i++) {
      switch (await runner.runOne()) {
        case ProgressSyncRunResult.committed:
          continue;
        case ProgressSyncRunResult.idle:
          return SyncRunResult.idle;
        case ProgressSyncRunResult.waitingForConsent:
          return SyncRunResult.waitingForConsent;
        case ProgressSyncRunResult.waitingForAuthentication:
          return SyncRunResult.waitingForAuthentication;
        case ProgressSyncRunResult.retryScheduled:
          return SyncRunResult.retryScheduled;
        case ProgressSyncRunResult.needsAttention:
          return SyncRunResult.needsAttention;
      }
    }
    return SyncRunResult.uploaded;
  }
}
