import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_firebase_session_controller.dart';

final class WebAccountPage extends ConsumerWidget {
  const WebAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webFirebaseSessionProvider);
    final port = ref.watch(webFirebaseAuthPortProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('帳號與同步')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                      ? '使用 Google 登入後，教材仍保存在這個瀏覽器。雲端同步功能尚未開放。'
                      : '目前教材仍保存在這個瀏覽器。登出後會回到離線教材庫。',
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
                    onPressed: state.busy
                        ? null
                        : () => unawaited(
                            ref
                                .read(webFirebaseSessionProvider.notifier)
                                .signOut(),
                          ),
                    child: const Text('登出'),
                  ),
                if (state.busy) ...[
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
}
