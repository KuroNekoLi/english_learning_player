import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_sign_in_view.dart';
import '../auth/firebase_session_controller.dart';
import '../auth/social_sign_in.dart';
import '../auth/test_email_sign_in_dialog.dart';
import '../library/library_view_model.dart';
import '../progress/domain/progress_models.dart';
import 'firebase_sync_view_model.dart';
import 'sync_preference.dart';
import 'widgets/sync_consent_controls.dart';
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
        .runAccountAction(
          () => ref
              .read(firebaseSessionProvider.notifier)
              .signIn(entered.email, entered.password),
          fallbackMessage: '登入失敗，請稍後重試。',
        );
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
    final uid = state.uid;
    final key =
        uid != null && endpoint != null && endpoint.isMediaSyncConfigured
        ? (uid: uid, project: endpoint.project)
        : null;
    final consent =
        key != null &&
        ref.watch(syncPreferenceProvider(key)).asData?.value ==
            SyncPreference.enabled;
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
                onSignIn: (provider) => viewModel.runAccountAction(
                  () => ref
                      .read(firebaseSessionProvider.notifier)
                      .signInWithProvider(provider),
                  fallbackMessage: '${provider.label} 登入失敗，請稍後重試。',
                ),
                onTestEmailSignIn: canUseTestEmail ? _signInForTesting : null,
              ),
            ] else ...[
              OutlinedButton(
                onPressed: sync.busy
                    ? null
                    : () => viewModel.runAccountAction(() async {
                        await ref
                            .read(firebaseSessionProvider.notifier)
                            .signOut();
                        if (mounted) viewModel.clear();
                      }, fallbackMessage: '登出失敗，請稍後重試。'),
                child: const Text('登出'),
              ),
              if (key != null)
                SyncConsentControls(
                  preferenceKey: key,
                  busy: sync.busy,
                  onSync: viewModel.sync,
                )
              else
                const Text('教材同步尚未設定。'),
            ],
            if (sync.busy) const LinearProgressIndicator(),
            if (sync.status case final message?)
              Semantics(liveRegion: true, child: Text(message)),
            if (consent)
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
