import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/library_view_model.dart';
import '../../progress/domain/progress_models.dart';
import '../../sync/firebase_sync_dependencies.dart';
import '../../sync/firebase_sync_view_model.dart';
import '../../sync/sync_preference.dart';
import '../../sync/widgets/sync_consent_controls.dart';
import '../../sync/widgets/cloud_material_entry.dart';
import '../../sync/widgets/progress_conflict_dialog.dart';
import 'web_firebase_session_controller.dart';

final class WebAccountPage extends ConsumerWidget {
  const WebAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webFirebaseSessionProvider);
    final port = ref.watch(webFirebaseAuthPortProvider);
    final sync = ref.watch(firebaseSyncViewModelProvider);
    final viewModel = ref.read(firebaseSyncViewModelProvider.notifier);
    final endpoint = ref.watch(firebaseMediaEndpointProvider);
    final uid = state.uid;
    final key =
        uid != null && endpoint != null && endpoint.isMediaSyncConfigured
        ? (uid: uid, project: endpoint.project)
        : null;
    final consent =
        key != null &&
        ref.watch(syncPreferenceProvider(key)).asData?.value ==
            SyncPreference.enabled;
    final local = sync.materials.isEmpty
        ? null
        : ref.watch(libraryViewModelProvider).value;
    final busy = state.busy || sync.busy;
    final syncBusy = busy || sync.isDownloading;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('帳號與同步')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  state.uid == null ? '登入同步帳號' : '已登入同步帳號',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  state.uid == null
                      ? '使用 Google 登入後，可以同步這個帳號的教材。'
                      : '登出後會回到離線教材庫。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (state.uid == null)
                  Semantics(
                    label: '使用 Google 登入',
                    button: true,
                    child: SizedBox(
                      width: 240,
                      height: 48,
                      child: OutlinedButton(
                        key: const ValueKey('webGoogleSignIn'),
                        onPressed: state.busy || !port.isConfigured
                            ? null
                            : () => unawaited(
                                ref
                                    .read(webFirebaseSessionProvider.notifier)
                                    .signInWithGoogle(),
                              ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/auth/google-sign-in.png',
                              height: 40,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  FilledButton.tonal(
                    key: const ValueKey('webSignOut'),
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            ref
                                .read(webFirebaseSessionProvider.notifier)
                                .signOut(),
                          ),
                    child: const Text('登出'),
                  ),
                if (key != null) ...[
                  SyncConsentControls(
                    preferenceKey: key,
                    busy: syncBusy,
                    onSync: viewModel.sync,
                  ),
                  if (sync.status case final message?)
                    Semantics(liveRegion: true, child: Text(message)),
                  if (consent)
                    for (final material in sync.materials)
                      CloudMaterialEntry(
                        material: material,
                        conflicts:
                            sync.conflicts[material.materialId] ?? const [],
                        isLocal:
                            local?.any(
                              (item) => item.id == material.materialId,
                            ) ??
                            false,
                        autoSyncEnabled: consent,
                        downloadProgress:
                            sync.downloadProgress[material.materialId],
                        onDownload: syncBusy
                            ? null
                            : () => viewModel.download(material),
                        onResolve: busy
                            ? null
                            : (candidate) =>
                                  _resolve(context, viewModel, candidate),
                      ),
                ] else if (state.uid != null)
                  const Text('教材同步尚未設定。'),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (state.message case final message?) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      key: const ValueKey('webAuthMessage'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ] else if (state.uid == null && !port.isConfigured) ...[
                  const SizedBox(height: 16),
                  Text(
                    port.unavailableReason ?? 'Firebase Web Auth 尚未設定。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    FirebaseSyncViewModel viewModel,
    ProgressCandidate candidate,
  ) async {
    final choice = await showProgressConflictDialog(context, candidate);
    if (choice != null && context.mounted) {
      await viewModel.resolve(candidate, choice);
    }
  }
}
