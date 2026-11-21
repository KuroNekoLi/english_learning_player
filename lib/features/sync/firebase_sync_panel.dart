import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_sign_in_view.dart';
import '../auth/social_sign_in.dart';
import '../auth/test_email_sign_in_dialog.dart';
import '../library/library_view_model.dart';
import '../progress/domain/progress_models.dart';
import 'firebase_sync_dependencies.dart';
import 'firebase_sync_view_model.dart';
import 'widgets/cloud_material_entry.dart';
import 'widgets/progress_conflict_dialog.dart';

final class FirebaseSyncPanel extends ConsumerStatefulWidget {
  const FirebaseSyncPanel({super.key});

  @override
  ConsumerState<FirebaseSyncPanel> createState() => _FirebaseSyncPanelState();
}

final class _FirebaseSyncPanelState extends ConsumerState<FirebaseSyncPanel> {
  Future<void> _signInForTesting() async {
    final entered = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) => const TestEmailSignInDialog(),
    );
    if (entered == null || !mounted) return;
    await ref
        .read(firebaseSyncViewModelProvider.notifier)
        .signInForTesting(entered.email, entered.password);
  }

  Future<void> _resolve(ProgressCandidate candidate) async {
    final choice = await showProgressConflictDialog(context, candidate);
    if (choice == null || !mounted) return;
    await ref
        .read(firebaseSyncViewModelProvider.notifier)
        .resolve(candidate, choice);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseSessionProvider);
    final sync = ref.watch(firebaseSyncViewModelProvider);
    final viewModel = ref.read(firebaseSyncViewModelProvider.notifier);
    final endpoint = ref.watch(firebaseEndpointProvider);
    final platform = ref.watch(socialSignInProvider);
    final canSync = endpoint?.isMediaSyncConfigured ?? false;
    final canUseTestEmail =
        endpoint != null &&
        (endpoint.isEmulator ||
            const bool.fromEnvironment('ELP_ENABLE_TEST_EMAIL_SIGN_IN'));
    final local = sync.materials.isEmpty
        ? null
        : ref.watch(libraryViewModelProvider).value;
    return PopScope(
      canPop: !sync.busy,
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
                busy: sync.busy,
                onSignIn: viewModel.signIn,
                onTestEmailSignIn: canUseTestEmail ? _signInForTesting : null,
              ),
            ] else ...[
              OutlinedButton(
                onPressed: sync.busy ? null : viewModel.signOut,
                child: const Text('登出'),
              ),
              if (canSync) ...[
                SwitchListTile(
                  title: const Text('允許同步這個帳號的教材'),
                  value: state.consent,
                  onChanged: sync.busy ? null : viewModel.setConsent,
                ),
                FilledButton(
                  onPressed: sync.busy || !state.consent
                      ? null
                      : viewModel.sync,
                  child: const Text('立即同步'),
                ),
              ] else
                const Text('教材同步尚未設定。'),
            ],
            if (sync.busy) const LinearProgressIndicator(),
            if (sync.status case final message?)
              Semantics(liveRegion: true, child: Text(message)),
            if (state.uid != null && canSync && state.consent)
              for (final material in sync.materials)
                CloudMaterialEntry(
                  material: material,
                  conflicts: sync.conflicts[material.materialId] ?? const [],
                  isLocal:
                      local?.any((item) => item.id == material.materialId) ??
                      false,
                  onDownload: sync.busy
                      ? null
                      : () => viewModel.download(material),
                  onResolve: sync.busy ? null : _resolve,
                ),
          ],
        ),
      ),
    );
  }
}
