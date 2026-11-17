import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_contracts.dart';
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

  Future<void> _run(Future<void> Function() action) async {
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
          SyncFailureKind.unauthenticated => '登入失敗或已過期，請重新登入。',
          SyncFailureKind.permissionDenied => '沒有這項同步權限。',
          SyncFailureKind.transient => 'Firebase 暫時無法連線，請稍後重試。',
          SyncFailureKind.invalidData => '同步資料未通過驗證。',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _status = '同步失敗，請稍後重試。');
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

  Future<void> _signIn() async {
    final entered = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) => const _SignInDialog(),
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
    final local = ref.watch(libraryViewModelProvider).value;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Firebase 同步')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.uid == null) ...[
              const Text('登入會切換到該帳號的教材庫。原本的離線教材仍可在登出後使用。'),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: const Text('登入'),
              ),
            ] else ...[
              OutlinedButton(
                onPressed: _busy ? null : controller.signOut,
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
            if (_status case final message?) Text(message),
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

final class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

final class _SignInDialogState extends State<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('登入 Firebase 帳號'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '電子郵件'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: '密碼'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
          Navigator.of(
            context,
          ).pop((email: _email.text, password: _password.text));
        },
        child: const Text('登入'),
      ),
    ],
  );
}
