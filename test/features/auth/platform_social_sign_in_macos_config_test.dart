import 'package:english_learning_player/features/auth/platform_social_sign_in.dart';
import 'package:english_learning_player/features/auth/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS Google availability requires configured desktop credentials', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const desktopId = String.fromEnvironment('ELP_GOOGLE_DESKTOP_CLIENT_ID');
    const desktopSecret = String.fromEnvironment(
      'ELP_GOOGLE_DESKTOP_CLIENT_SECRET',
    );
    const nativeId = String.fromEnvironment('ELP_GOOGLE_MACOS_CLIENT_ID');
    const webId = String.fromEnvironment('ELP_GOOGLE_SERVER_CLIENT_ID');
    final expected =
        (desktopId.isNotEmpty && desktopSecret.isNotEmpty) ||
        (nativeId.isNotEmpty && webId.isNotEmpty);
    final social = PlatformSocialSignIn(
      project: 'test-project',
      apiKey: 'test-key',
    );
    expect(social.isConfigured(SocialProvider.google), expected);
    expect(social.isConfigured(SocialProvider.apple), isFalse);
  });
}
