import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/sync/sync_contracts.dart';
import '../dictionary/dictionary_dependencies.dart';
import '../library/library_view_model.dart';
import '../library/library_folder_view_model.dart';
import '../progress/domain/progress_models.dart';
import 'firebase_sync_dependencies.dart';
import 'services/cloud_sync_coordinator.dart';
import 'sync_preference.dart';

final firebaseSyncViewModelProvider =
    NotifierProvider.autoDispose<FirebaseSyncViewModel, FirebaseSyncViewState>(
      FirebaseSyncViewModel.new,
    );

final class FirebaseSyncViewState {
  const FirebaseSyncViewState({
    this.busy = false,
    this.status,
    this.materials = const [],
    this.conflicts = const {},
    this.downloadProgress = const {},
  });

  final bool busy;
  final String? status;
  final List<CloudMaterialMetadata> materials;
  final Map<String, List<ProgressCandidate>> conflicts;
  final Map<String, CloudDownloadProgress> downloadProgress;

  bool get isDownloading => downloadProgress.values.any(
    (progress) =>
        progress.phase == CloudDownloadPhase.audio ||
        progress.phase == CloudDownloadPhase.subtitles,
  );

  FirebaseSyncViewState copyWith({
    bool? busy,
    String? status,
    bool clearStatus = false,
    List<CloudMaterialMetadata>? materials,
    Map<String, List<ProgressCandidate>>? conflicts,
    Map<String, CloudDownloadProgress>? downloadProgress,
  }) => FirebaseSyncViewState(
    busy: busy ?? this.busy,
    status: clearStatus ? null : status ?? this.status,
    materials: materials ?? this.materials,
    conflicts: conflicts ?? this.conflicts,
    downloadProgress: downloadProgress ?? this.downloadProgress,
  );
}

final class FirebaseSyncViewModel extends Notifier<FirebaseSyncViewState> {
  @override
  FirebaseSyncViewState build() {
    ref.watch(accountScopeProvider);
    _retryAfter = null;
    return const FirebaseSyncViewState();
  }

  DateTime? _retryAfter;
  final Set<String> _activeDownloads = {};
  final Map<String, DateTime> _downloadRetryAfter = {};

  Future<void> syncAutomatically({required bool refreshCatalog}) async {
    if (state.busy || (_retryAfter?.isAfter(DateTime.now()) ?? false)) return;
    final owner = ref.read(accountScopeProvider).ownerId;
    try {
      final runtime = await _runtime();
      if (!await _canPresent(runtime)) return;
      final wordBankIssue = await _syncWordBank(
        runtime,
        refresh: refreshCatalog,
      );
      if (!await _canPresent(runtime)) return;
      if (wordBankIssue != null && !state.busy) {
        state = state.copyWith(status: wordBankIssue);
      }
      final due = await runtime.hasDueMedia(DateTime.now());
      if (!due && !refreshCatalog) return;
      if (due) {
        final result = await runtime.sync(mediaOnly: true);
        if (!await _canPresent(runtime)) return;
        ref.invalidate(libraryViewModelProvider);
        if (!state.busy) state = state.copyWith(status: _message(result));
        if (result == SyncRunResult.waitingForAuthentication ||
            result == SyncRunResult.waitingForConsent) {
          return;
        }
        if (result == SyncRunResult.retryScheduled ||
            result == SyncRunResult.needsAttention) {
          if (!refreshCatalog) return;
        }
      }
      final catalog = await runtime.refresh();
      if (!await _canPresent(runtime) || state.busy) return;
      _refreshLibrary();
      state = state.copyWith(materials: List.unmodifiable(catalog));
      await _downloadMissing(runtime, catalog);
    } catch (error) {
      // A failed preflight does not claim a job, so pace the next automatic attempt.
      if (!ref.mounted || ref.read(accountScopeProvider).ownerId != owner) {
        return;
      }
      _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      if (!state.busy &&
          error is SyncFailure &&
          error.code != 'consent_required') {
        state = state.copyWith(status: _failureMessage(error));
      }
    }
  }

  Future<bool> _canPresent(FirebaseSyncRuntime runtime) async {
    final allowed = await runtime.consent.isCloudSyncEnabled(runtime.uid);
    return allowed &&
        ref.mounted &&
        ref.read(accountScopeProvider).ownerId == runtime.scopeId;
  }

  Future<void> runAccountAction(
    Future<void> Function() action, {
    required String fallbackMessage,
  }) => _run(action, fallbackMessage: fallbackMessage);

  void clear() => state = const FirebaseSyncViewState();

  void clearDownloadProgress() => state = state.copyWith(downloadProgress: {});

  Future<void> sync() => _run(() async {
    final runtime = await _runtime();
    final wordBankIssue = await _syncWordBank(runtime, refresh: true);
    if (!await _canPresent(runtime)) return;
    final result = await runtime.sync();
    if (!ref.mounted) return;
    ref.invalidate(libraryViewModelProvider);
    if (result == SyncRunResult.waitingForConsent ||
        result == SyncRunResult.waitingForAuthentication) {
      state = state.copyWith(status: _message(result));
      return;
    }
    state = state.copyWith(status: _message(result));
    final catalog = await runtime.refresh();
    final conflicts = {
      for (final material in catalog)
        material.materialId: List<ProgressCandidate>.unmodifiable(
          await runtime.conflicts(material.materialId),
        ),
    };
    if (!await _canPresent(runtime)) {
      return;
    }
    _refreshLibrary();
    state = state.copyWith(
      busy: true,
      materials: List.unmodifiable(catalog),
      conflicts: Map.unmodifiable(conflicts),
      status: wordBankIssue ?? _message(result),
    );
    await _downloadMissing(runtime, catalog);
  });

  Future<String?> _syncWordBank(
    FirebaseSyncRuntime runtime, {
    required bool refresh,
  }) async {
    try {
      final changed = await runtime.wordBank?.run(refresh: refresh) ?? false;
      if (changed && await _canPresent(runtime)) {
        ref.invalidate(savedDictionaryWordsProvider);
      }
      return null;
    } catch (_) {
      return '單字庫同步暫時失敗，已保留本機收藏和待送變更。';
    }
  }

  void _refreshLibrary() {
    ref.invalidate(libraryViewModelProvider);
    ref.invalidate(libraryFoldersProvider);
    ref.invalidate(folderMaterialsProvider);
    ref.invalidate(libraryAssignedMaterialsProvider);
  }

  String _message(SyncRunResult result) => switch (result) {
    SyncRunResult.uploaded => '已送出一批教材，可以繼續同步。',
    SyncRunResult.idle => '教材清單已更新。',
    SyncRunResult.retryScheduled => '暫時無法上傳，操作已留在佇列。',
    SyncRunResult.needsAttention => '有同步操作需要檢查。',
    SyncRunResult.waitingForAuthentication => '請重新登入以繼續同步。',
    SyncRunResult.waitingForConsent => '請先允許同步。',
  };

  Future<void> download(CloudMaterialMetadata metadata) => _run(() async {
    final runtime = await _runtime();
    await _downloadOne(runtime, metadata, force: true);
  });

  Future<void> _downloadMissing(
    FirebaseSyncRuntime runtime,
    List<CloudMaterialMetadata> catalog,
  ) async {
    final localIds = (await runtime.repository.listMaterials())
        .map((material) => material.id)
        .toSet();
    if (!await _canPresent(runtime)) return;
    final catalogIds = catalog.map((item) => item.materialId).toSet();
    final missing = catalog
        .where((material) => !localIds.contains(material.materialId))
        .toList();
    final progress = Map<String, CloudDownloadProgress>.of(
      state.downloadProgress,
    );
    progress.removeWhere(
      (id, _) => !catalogIds.contains(id) || localIds.contains(id),
    );
    for (final material in missing) {
      final key = _downloadKey(runtime.uid, material.materialId);
      final retryAt = _downloadRetryAfter[key];
      if (retryAt?.isAfter(DateTime.now()) ?? false) continue;
      if (_activeDownloads.contains(key)) continue;
      progress[material.materialId] = CloudDownloadProgress(
        materialId: material.materialId,
        title: material.title,
        phase: CloudDownloadPhase.queued,
        bytesDownloaded: 0,
        totalBytes: material.byteLength,
      );
    }
    if (ref.mounted) {
      state = state.copyWith(downloadProgress: Map.unmodifiable(progress));
    }
    for (final material in missing) {
      if (!await _canPresent(runtime)) return;
      final retryAt =
          _downloadRetryAfter[_downloadKey(runtime.uid, material.materialId)];
      if (retryAt?.isAfter(DateTime.now()) ?? false) continue;
      await _downloadOne(runtime, material);
    }
  }

  Future<void> _downloadOne(
    FirebaseSyncRuntime runtime,
    CloudMaterialMetadata metadata, {
    bool force = false,
  }) async {
    final uid = runtime.uid;
    if (await runtime.isMaterialDeleted(metadata.materialId) ||
        !await _canPresent(runtime)) {
      return;
    }
    final key = _downloadKey(uid, metadata.materialId);
    if (!_activeDownloads.add(key)) return;
    final retryAt = _downloadRetryAfter[key];
    if (!force && (retryAt?.isAfter(DateTime.now()) ?? false)) {
      _activeDownloads.remove(key);
      return;
    }
    var phase = CloudDownloadPhase.queued;
    var bytesDownloaded = 0;
    _publishDownloadProgress(
      uid,
      CloudDownloadProgress(
        materialId: metadata.materialId,
        title: metadata.title,
        phase: phase,
        bytesDownloaded: 0,
        totalBytes: metadata.byteLength,
      ),
    );
    try {
      await runtime.download(
        metadata,
        onProgress: (received, total) {
          phase = CloudDownloadPhase.audio;
          bytesDownloaded = received;
          _publishDownloadProgress(
            uid,
            CloudDownloadProgress(
              materialId: metadata.materialId,
              title: metadata.title,
              phase: phase,
              bytesDownloaded: received,
              totalBytes: total,
            ),
          );
        },
        onAudioCached: () {
          if (ref.mounted && ref.read(accountScopeProvider).ownerId == uid) {
            _refreshLibrary();
          }
        },
        onPhaseChanged: (nextPhase) {
          phase = nextPhase;
          _publishDownloadProgress(
            uid,
            CloudDownloadProgress(
              materialId: metadata.materialId,
              title: metadata.title,
              phase: phase,
              bytesDownloaded: bytesDownloaded,
              totalBytes: metadata.byteLength,
              audioCached: phase == CloudDownloadPhase.subtitles,
            ),
          );
        },
      );
      if (!await _canPresent(runtime)) {
        _removeDownloadProgress(uid, metadata.materialId);
        return;
      }
      _downloadRetryAfter.remove(key);
      ref.invalidate(libraryViewModelProvider);
      _removeDownloadProgress(uid, metadata.materialId);
    } catch (error) {
      if (!ref.mounted || ref.read(accountScopeProvider).ownerId != uid) {
        return;
      }
      if (error is SyncFailure && error.code == 'consent_required') {
        _removeDownloadProgress(uid, metadata.materialId);
        return;
      }
      var cached = false;
      try {
        cached =
            await runtime.repository.audioAssetForMaterial(
              metadata.materialId,
            ) !=
            null;
      } catch (_) {
        // Keep the visible failure state if the local cache query also fails.
      }
      if (cached) ref.invalidate(libraryViewModelProvider);
      _downloadRetryAfter[key] = DateTime.now().add(
        const Duration(seconds: 30),
      );
      _publishDownloadProgress(
        uid,
        CloudDownloadProgress(
          materialId: metadata.materialId,
          title: metadata.title,
          phase: CloudDownloadPhase.failed,
          bytesDownloaded: bytesDownloaded,
          totalBytes: metadata.byteLength,
          audioCached: cached || phase == CloudDownloadPhase.subtitles,
        ),
      );
    } finally {
      _activeDownloads.remove(key);
    }
  }

  void _publishDownloadProgress(String uid, CloudDownloadProgress progress) {
    if (!_canUpdateDownloadProgress(uid)) return;
    state = state.copyWith(
      downloadProgress: Map.unmodifiable({
        ...state.downloadProgress,
        progress.materialId: progress,
      }),
    );
  }

  void _removeDownloadProgress(String uid, String materialId) {
    if (!ref.mounted || ref.read(accountScopeProvider).ownerId != uid) return;
    final progress = Map<String, CloudDownloadProgress>.of(
      state.downloadProgress,
    )..remove(materialId);
    state = state.copyWith(downloadProgress: Map.unmodifiable(progress));
  }

  bool _canUpdateDownloadProgress(String uid) {
    if (!ref.mounted || ref.read(accountScopeProvider).ownerId != uid) {
      return false;
    }
    final endpoint = ref.read(firebaseMediaEndpointProvider);
    if (endpoint == null) return false;
    final key = (uid: uid, project: endpoint.project);
    return ref.read(syncPreferenceProvider(key)).asData?.value ==
        SyncPreference.enabled;
  }

  String _downloadKey(String uid, String materialId) => '$uid::$materialId';

  Future<void> resolve(ProgressCandidate candidate, bool useCandidate) =>
      _run(() async {
        final runtime = await _runtime();
        await runtime.resolve(candidate, useCandidate);
        if (ref.mounted &&
            ref.read(accountScopeProvider).ownerId == runtime.scopeId) {
          state = state.copyWith(status: '已排入進度選擇。請再次同步以確認。');
        }
      });

  Future<FirebaseSyncRuntime> _runtime() async {
    final runtime = await ref.read(firebaseSyncRuntimeProvider.future);
    if (runtime == null) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'sign_in_required',
      );
    }
    return runtime;
  }

  String _failureMessage(SyncFailure error) => switch (error.kind) {
    SyncFailureKind.unauthenticated =>
      error.code == 'sign_in_account_link_required'
          ? '這個帳號已有其他登入方式，請使用原本的登入方式。'
          : '登入失敗或已過期，請重新登入。',
    SyncFailureKind.permissionDenied => '沒有這項同步權限。',
    SyncFailureKind.transient => 'Firebase 暫時無法連線，請稍後重試。',
    SyncFailureKind.invalidData => '同步資料未通過驗證。',
  };

  Future<void> _run(
    Future<void> Function() action, {
    String fallbackMessage = '同步失敗，請稍後重試。',
  }) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearStatus: true);
    try {
      await action();
    } on SyncFailure catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(status: _failureMessage(error));
    } catch (_) {
      if (ref.mounted) state = state.copyWith(status: fallbackMessage);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }
}
