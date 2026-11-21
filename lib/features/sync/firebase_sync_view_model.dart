import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_contracts.dart';
import '../auth/social_sign_in.dart';
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
  FirebaseSyncViewState build() => const FirebaseSyncViewState();

  FirebaseSessionController get _session =>
      ref.read(firebaseSessionProvider.notifier);

  Future<void> signIn(SocialProvider provider) => _run(
    () => _session.signInWithProvider(provider),
    fallbackMessage: '${provider.label} 登入失敗，請稍後重試。',
  );

  Future<void> signInForTesting(String email, String password) =>
      _run(() => _session.signIn(email, password));

  Future<void> signOut() => _run(() async {
    await _session.signOut();
    if (ref.mounted) state = const FirebaseSyncViewState(busy: true);
  }, fallbackMessage: '登出失敗，請稍後重試。');

  void setConsent(bool enabled) {
    _session.setConsent(enabled);
    if (!enabled) state = const FirebaseSyncViewState();
  }

  Future<void> sync() => _run(() async {
    final runtime = await _runtime();
    final result = await runtime.sync();
    if (!ref.mounted) return;
    ref.invalidate(libraryViewModelProvider);
    final catalog = await runtime.refresh();
    final conflicts = {
      for (final material in catalog)
        material.materialId: List<ProgressCandidate>.unmodifiable(
          await runtime.conflicts(material.materialId),
        ),
    };
    if (!ref.mounted || ref.read(firebaseSessionProvider).uid != runtime.uid) {
      return;
    }
    state = FirebaseSyncViewState(
      busy: true,
      materials: List.unmodifiable(catalog),
      conflicts: Map.unmodifiable(conflicts),
      status: switch (result) {
        SyncRunResult.uploaded => '已送出一批教材，可以繼續同步。',
        SyncRunResult.idle => '教材清單已更新。',
        SyncRunResult.retryScheduled => '暫時無法上傳，操作已留在佇列。',
        SyncRunResult.needsAttention => '有同步操作需要檢查。',
        SyncRunResult.waitingForAuthentication => '請重新登入以繼續同步。',
        SyncRunResult.waitingForConsent => '請先允許同步。',
      },
    );
  });

  Future<void> download(CloudMaterialMetadata metadata) => _run(() async {
    final runtime = await _runtime();
    await runtime.download(metadata);
    if (!ref.mounted || ref.read(firebaseSessionProvider).uid != runtime.uid) {
      return;
    }
    ref.invalidate(libraryViewModelProvider);
    state = state.copyWith(status: '已下載「${metadata.title}」。');
  });

  Future<void> resolve(ProgressCandidate candidate, bool useCandidate) => _run(
    () async {
      final runtime = await _runtime();
      await runtime.resolve(candidate, useCandidate);
      if (ref.mounted && ref.read(firebaseSessionProvider).uid == runtime.uid) {
        state = state.copyWith(status: '已排入進度選擇。請再次同步以確認。');
      }
    },
  );

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
      state = state.copyWith(
        status: switch (error.kind) {
          SyncFailureKind.unauthenticated =>
            error.code == 'sign_in_account_link_required'
                ? '這個帳號已有其他登入方式，請使用原本的登入方式。'
                : '登入失敗或已過期，請重新登入。',
          SyncFailureKind.permissionDenied => '沒有這項同步權限。',
          SyncFailureKind.transient => 'Firebase 暫時無法連線，請稍後重試。',
          SyncFailureKind.invalidData => '同步資料未通過驗證。',
        },
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(status: fallbackMessage);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }
}
