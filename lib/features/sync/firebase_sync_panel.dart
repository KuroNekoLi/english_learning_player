import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_sign_in_view.dart';
import '../auth/firebase_session_controller.dart';
import '../auth/social_sign_in.dart';
import '../auth/username_password_dialog.dart';
import '../auth/link_read_only_username_dialog.dart';
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
  Future<void> _signInWithUsername() async {
    final entered = await showDialog<({String username, String password})>(
      context: context,
      builder: (_) => const UsernamePasswordDialog(),
    );
    if (entered == null || !mounted) return;
    await ref
        .read(firebaseSyncViewModelProvider.notifier)
        .runAccountAction(
          () => ref
              .read(firebaseSessionProvider.notifier)
              .signInWithUsername(entered.username, entered.password),
          fallbackMessage: '登入失敗，請稍後重試。',
        );
  }

  Future<void> _provisionReadOnlyUsername() async {
    final entered = await showDialog<({String username, String password})>(
      context: context,
      builder: (_) => const LinkReadOnlyUsernameDialog(),
    );
    if (entered == null || !mounted) return;
    await ref.read(firebaseSyncViewModelProvider.notifier).runAccountAction(
      () async {
        await ref
            .read(firebaseSessionProvider.notifier)
            .provisionReadOnlyLogin(
              username: entered.username,
              password: entered.password,
            );
      },
      fallbackMessage: '設定唯讀帳號失敗，請稍後重試。',
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
    final syncBusy = sync.busy || sync.isDownloading;
    final key =
        uid != null && endpoint != null && endpoint.isMediaSyncConfigured
        ? (uid: uid, project: endpoint.project)
        : null;
    final consent =
        key != null &&
        ref.watch(syncPreferenceProvider(key)).asData?.value ==
            SyncPreference.enabled;
    final canUseUsernamePassword = endpoint != null;
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
                onUsernamePasswordSignIn: canUseUsernamePassword
                    ? _signInWithUsername
                    : null,
              ),
            ] else ...[
              if (state.readOnly)
                const ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('帳號密碼登入：唯讀'),
                  subtitle: Text('可以讀取與下載教材；雲端不接受上傳、修改或刪除。'),
                ),
              if (state.canProvisionReadOnlyLogin)
                OutlinedButton.icon(
                  key: const ValueKey('provisionReadOnlyUsername'),
                  onPressed: sync.busy ? null : _provisionReadOnlyUsername,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('建立帳號密碼唯讀登入'),
                ),
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
                  busy: syncBusy,
                  onSync: viewModel.sync,
                  readOnly: state.readOnly,
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
                  autoSyncEnabled: consent,
                  downloadProgress: sync.downloadProgress[material.materialId],
                  onDownload: syncBusy
                      ? null
                      : () => viewModel.download(material),
                  onResolve: sync.busy || state.readOnly ? null : _resolve,
                ),
          ],
        ),
      ),
    );
  }
}
