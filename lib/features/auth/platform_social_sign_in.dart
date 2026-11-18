import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/sync/sync_contracts.dart';
import 'social_sign_in.dart';

final class PlatformSocialSignIn implements SocialSignIn {
  PlatformSocialSignIn({required this.project, required this.apiKey});

  final String project;
  final String apiKey;

  static const _androidApple = MethodChannel('elp/firebase_apple_auth');
  static const _androidAppId = String.fromEnvironment(
    'ELP_FIREBASE_ANDROID_APP_ID',
  );
  static const _enableApple = bool.fromEnvironment('ELP_ENABLE_APPLE_SIGN_IN');
  static const _googleServerId = String.fromEnvironment(
    'ELP_GOOGLE_SERVER_CLIENT_ID',
  );
  static Future<void>? _googleInitialization;

  String get _googleClientId => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => const String.fromEnvironment(
      'ELP_GOOGLE_IOS_CLIENT_ID',
    ),
    TargetPlatform.macOS => const String.fromEnvironment(
      'ELP_GOOGLE_MACOS_CLIENT_ID',
    ),
    _ => '',
  };

  @override
  bool isConfigured(SocialProvider provider) => switch (provider) {
    SocialProvider.google => switch (defaultTargetPlatform) {
      TargetPlatform.android => _googleServerId.isNotEmpty,
      TargetPlatform.iOS || TargetPlatform.macOS =>
        _googleClientId.isNotEmpty && _googleServerId.isNotEmpty,
      _ => false,
    },
    SocialProvider.apple =>
      _enableApple &&
          switch (defaultTargetPlatform) {
            TargetPlatform.android => _androidAppId.isNotEmpty,
            TargetPlatform.iOS || TargetPlatform.macOS => true,
            _ => false,
          },
  };

  @override
  Future<SocialSignInResult?> signIn(SocialProvider provider) async {
    if (!isConfigured(provider)) {
      throw StateError('The requested sign-in provider is not configured.');
    }
    return switch (provider) {
      SocialProvider.google => _signInWithGoogle(),
      SocialProvider.apple =>
        defaultTargetPlatform == TargetPlatform.android
            ? _signInWithAppleOnAndroid()
            : _signInWithAppleOnDarwin(),
    };
  }

  Future<ProviderIdToken?> _signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    await (_googleInitialization ??= google.initialize(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      serverClientId: _googleServerId,
    ));
    try {
      final user = await google.authenticate();
      final token = user.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw StateError('Google did not return an ID token.');
      }
      return ProviderIdToken(token);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<ProviderIdToken?> _signInWithAppleOnDarwin() async {
    if (!await SignInWithApple.isAvailable()) {
      throw StateError('Apple sign-in is unavailable on this device.');
    }
    final random = Random.secure();
    final rawNonce = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw StateError('Apple did not return an ID token.');
      }
      return ProviderIdToken(token, rawNonce: rawNonce);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  Future<NativeFirebaseUser?> _signInWithAppleOnAndroid() async {
    final String? uid;
    try {
      uid = await _androidApple.invokeMethod<String>('signIn', {
        'project': project,
        'apiKey': apiKey,
        'appId': _androidAppId,
      });
    } on PlatformException catch (error) {
      throw _mapAndroidError(error);
    }
    if (uid == null) return null;
    return NativeFirebaseUser(uid, () async {
      final String? token;
      try {
        token = await _androidApple.invokeMethod<String>('getIdToken', uid);
      } on PlatformException catch (error) {
        throw _mapAndroidError(error);
      }
      if (token == null || token.isEmpty) {
        throw const SyncFailure(
          SyncFailureKind.unauthenticated,
          'missing_token',
        );
      }
      return token;
    });
  }

  SyncFailure _mapAndroidError(PlatformException error) => switch (error.code) {
    'account-link-required' => const SyncFailure(
      SyncFailureKind.unauthenticated,
      'sign_in_account_link_required',
    ),
    'network-unavailable' => const SyncFailure(
      SyncFailureKind.transient,
      'network_unavailable',
    ),
    _ => const SyncFailure(SyncFailureKind.unauthenticated, 'sign_in_rejected'),
  };

  @override
  Future<void> signOut(SocialProvider provider) async {
    switch (provider) {
      case SocialProvider.google:
        if (_googleInitialization != null) {
          await _googleInitialization;
          await GoogleSignIn.instance.signOut();
        }
      case SocialProvider.apple:
        if (defaultTargetPlatform == TargetPlatform.android) {
          await _androidApple.invokeMethod<void>('signOut');
        }
    }
  }
}
