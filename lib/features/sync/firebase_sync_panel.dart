import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_contracts.dart';
import '../auth/account_sign_in_view.dart';
import '../auth/social_sign_in.dart';
import '../auth/test_email_sign_in_dialog.dart';
import '../library/library_view_model.dart';
import '../progress/domain/progress_models.dart';
import 'firebase_sync_dependencies.dart';
import 'services/cloud_sync_coordinator.dart';

final class FirebaseSyncPanel extends ConsumerStatefulWidget {
  const FirebaseSyncPanel({super.key});

  @override
  ConsumerState<FirebaseSyncPanel> createState() => _FirebaseSyncPanelState();
}

final class _FirebaseSyncPanelState extends ConsumerState<FirebaseSyncPanel> {
  bool _busy = false;
  String? _status;
  List<CloudMaterialMetadata> _cloud = const [];
  Map<String, List<ProgressCandidate>> _conflicts = const {};

  Future<void> _run(
    Future<void> Function() action, {
    String fallbackMessage = '同步失敗，請稍後重試。',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } on SyncFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _status = switch (error.kind) {
          SyncFailureKind.unauthenticated =>
            error.code == 'sign_in_account_link_required'
                ? '這個帳號已有其他登入方式，請使用原本的登入方式。'
                : '登入失敗或已過期，請重新登入。',
          SyncFailureKind.permissionDenied => '沒有這項同步權限。',
          SyncFailureKind.transient => 'Firebase 暫時無法連線，請稍後重試。',
          SyncFailureKind.invalidData => '同步資料未通過驗證。',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _status = fallbackMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  Future<void> _signInForTesting() async {
    final entered = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) => const TestEmailSignInDialog(),
    );
    if (entered == null || !mounted) return;
    await _run(
      () => ref
          .read(firebaseSessionProvider.notifier)
          .signIn(entered.email, entered.password),
    );
  }

  Future<void> _sync() => _run(() async {
    final runtime = await _runtime();
    final result = await runtime.sync();
    if (!mounted) return;
    ref.invalidate(libraryViewModelProvider);
    final cloud = await runtime.refresh();
    final conflicts = {
      for (final material in cloud)
        material.materialId: await runtime.conflicts(material.materialId),
    };
    if (!mounted) return;
    setState(() {
      _cloud = cloud;
      _conflicts = conflicts;
      _status = switch (result) {
        SyncRunResult.uploaded => '已送出一批教材，可以繼續同步。',
        SyncRunResult.idle => '教材清單已更新。',
        SyncRunResult.retryScheduled => '暫時無法上傳，操作已留在佇列。',
        SyncRunResult.needsAttention => '有同步操作需要檢查。',
        SyncRunResult.waitingForAuthentication => '請重新登入以繼續同步。',
        SyncRunResult.waitingForConsent => '請先允許同步。',
      };
    });
  });

  Future<void> _download(CloudMaterialMetadata metadata) => _run(() async {
    final runtime = await _runtime();
    await runtime.download(metadata);
    if (!mounted) return;
    ref.invalidate(libraryViewModelProvider);
    setState(() => _status = '已下載「${metadata.title}」。');
  });

  Future<void> _resolve(ProgressCandidate candidate) async {
    final seconds = candidate.checkpoint.positionMs ~/ 1000;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選擇續播位置'),
        content: Text('此裝置保留了一筆離線進度，位置為 $seconds 秒。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留雲端位置'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('採用離線位置'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _run(() async {
      final runtime = await _runtime();
      await runtime.resolve(candidate, choice);
      if (mounted) setState(() => _status = '已排入進度選擇。請再次同步以確認。');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseSessionProvider);
    final controller = ref.read(firebaseSessionProvider.notifier);
    final endpoint = ref.watch(firebaseEndpointProvider);
    final platform = ref.watch(socialSignInProvider);
    final canUseTestEmail =
        endpoint != null &&
        (endpoint.isEmulator ||
            const bool.fromEnvironment('ELP_ENABLE_TEST_EMAIL_SIGN_IN'));
    final local = _cloud.isEmpty
        ? null
        : ref.watch(libraryViewModelProvider).value;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('帳號與同步')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.uid == null) ...[
              AccountSignInView(
                configuredProviders: {
                  for (final provider in SocialProvider.values)
                    if (platform?.isConfigured(provider) == true) provider,
                },
                busy: _busy,
                onSignIn: (provider) => _run(
                  () => controller.signInWithProvider(provider),
                  fallbackMessage: '${provider.label} 登入失敗，請稍後重試。',
                ),
                onTestEmailSignIn: canUseTestEmail ? _signInForTesting : null,
              ),
            ] else ...[
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        setState(() {
                          _cloud = const [];
                          _conflicts = const {};
                        });
                        await controller.signOut();
                      }),
                child: const Text('登出'),
              ),
              SwitchListTile(
                title: const Text('允許同步這個帳號的教材'),
                value: state.consent,
                onChanged: _busy
                    ? null
                    : (enabled) {
                        controller.setConsent(enabled);
                        if (!enabled) setState(() => _cloud = const []);
                      },
              ),
              FilledButton(
                onPressed: _busy || !state.consent ? null : _sync,
                child: const Text('立即同步'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_status case final message?)
              Semantics(liveRegion: true, child: Text(message)),
            if (state.uid != null && state.consent)
              for (final material in _cloud) ...[
                ListTile(
                  title: Text(material.title),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _download(material),
                    child: Text(
                      local?.any((item) => item.id == material.materialId) ==
                              true
                          ? '重新下載'
                          : '下載',
                    ),
                  ),
                ),
                for (final candidate
                    in _conflicts[material.materialId] ??
                        const <ProgressCandidate>[])
                  TextButton(
                    onPressed: _busy ? null : () => _resolve(candidate),
                    child: Text('選擇「${material.title}」的續播位置'),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}
