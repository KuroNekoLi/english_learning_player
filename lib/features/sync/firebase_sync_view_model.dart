import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/sync/sync_contracts.dart';
import '../library/library_view_model.dart';
import '../progress/domain/progress_models.dart';
import 'firebase_sync_dependencies.dart';
import 'services/cloud_sync_coordinator.dart';

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
  });

  final bool busy;
  final String? status;
  final List<CloudMaterialMetadata> materials;
  final Map<String, List<ProgressCandidate>> conflicts;

  FirebaseSyncViewState copyWith({
    bool? busy,
    String? status,
    bool clearStatus = false,
  }) => FirebaseSyncViewState(
    busy: busy ?? this.busy,
    status: clearStatus ? null : status ?? this.status,
    materials: materials,
    conflicts: conflicts,
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

  Future<void> syncAutomatically({required bool refreshCatalog}) async {
    if (state.busy || (_retryAfter?.isAfter(DateTime.now()) ?? false)) return;
    final owner = ref.read(accountScopeProvider).ownerId;
    try {
      final runtime = await _runtime();
      if (!await _canPresent(runtime)) return;
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
      state = FirebaseSyncViewState(
        status: state.status,
        materials: List.unmodifiable(catalog),
        conflicts: state.conflicts,
      );
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
        ref.read(accountScopeProvider).ownerId == runtime.uid;
  }

  Future<void> runAccountAction(
    Future<void> Function() action, {
    required String fallbackMessage,
  }) => _run(action, fallbackMessage: fallbackMessage);

  void clear() => state = const FirebaseSyncViewState();

  Future<void> sync() => _run(() async {
    final runtime = await _runtime();
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
    state = FirebaseSyncViewState(
      busy: true,
      materials: List.unmodifiable(catalog),
      conflicts: Map.unmodifiable(conflicts),
      status: _message(result),
    );
  });

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
    await runtime.download(metadata);
    if (!await _canPresent(runtime)) {
      return;
    }
    ref.invalidate(libraryViewModelProvider);
    state = state.copyWith(status: '已下載「${metadata.title}」。');
  });

  Future<void> resolve(ProgressCandidate candidate, bool useCandidate) =>
      _run(() async {
        final runtime = await _runtime();
        await runtime.resolve(candidate, useCandidate);
        if (ref.mounted &&
            ref.read(accountScopeProvider).ownerId == runtime.uid) {
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
