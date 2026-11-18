import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'social_sign_in.dart';

final class AccountSignInView extends StatelessWidget {
  const AccountSignInView({
    super.key,
    required this.configuredProviders,
    required this.busy,
    required this.onSignIn,
    this.onTestEmailSignIn,
  });

  final Set<SocialProvider> configuredProviders;
  final bool busy;
  final ValueChanged<SocialProvider> onSignIn;
  final VoidCallback? onTestEmailSignIn;

  @override
  Widget build(BuildContext context) {
    final googleReady = configuredProviders.contains(SocialProvider.google);
    final appleReady = configuredProviders.contains(SocialProvider.apple);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.account_circle_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('登入同步帳號', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              '在不同裝置使用同一帳號下載教材、接續播放。登出後可回到離線教材庫。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 210,
              height: 44,
              child: Semantics(
                label: '使用 Google 登入',
                child: OutlinedButton(
                  onPressed: busy || !googleReady
                      ? null
                      : () => onSignIn(SocialProvider.google),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Opacity(
                    opacity: busy || !googleReady ? 0.45 : 1,
                    child: Image.asset(
                      'assets/auth/google-sign-in.png',
                      height: 44,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
              child: SignInWithAppleButton(
                key: const ValueKey('appleSignIn'),
                height: 44,
                text: '使用 Apple 登入',
                onPressed: busy || !appleReady
                    ? null
                    : () => onSignIn(SocialProvider.apple),
              ),
            ),
            if (!googleReady || !appleReady) ...[
              const SizedBox(height: 12),
              Text(
                '尚未設定的登入方式：${SocialProvider.values.where((provider) => !configuredProviders.contains(provider)).map((provider) => provider.label).join('、')}。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onTestEmailSignIn != null)
              TextButton(
                onPressed: busy ? null : onTestEmailSignIn,
                child: const Text('使用測試帳號'),
              ),
          ],
        ),
      ),
    );
  }
}
