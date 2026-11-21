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
  const FirebaseSyncRuntime({
    required this.uid,
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

  Future<void> download(CloudMaterialMetadata metadata) async {
    await downloader.download(metadata);
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
  Future<SyncRunResult> sync() async {
    for (var i = 0; i < 20; i++) {
      final status = await coordinator.runOne();
      if (status == SyncRunResult.idle) {
        for (final materialId in await repository.uploadedMaterialIds()) {
          await subtitles.publish(materialId);
        }
        return _syncProgress();
      }
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
