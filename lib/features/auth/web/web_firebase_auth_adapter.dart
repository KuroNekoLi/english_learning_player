import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'web_firebase_auth_port.dart';

/// Firebase JavaScript SDK adapter used only by the Flutter Web entry.
///
/// Configuration is public Firebase Web app metadata. It is supplied through
/// `--dart-define-from-file=.env.firebase-web`, never from native OAuth secrets.
final class WebFirebaseAuthAdapter implements WebFirebaseAuthPort {
  WebFirebaseAuthAdapter._({
    required this.isConfigured,
    this.unavailableReason,
  });

  static const _project = String.fromEnvironment('ELP_FIREBASE_PROJECT');
  static const _apiKey = String.fromEnvironment('ELP_FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('ELP_FIREBASE_WEB_APP_ID');
  static const _senderId = String.fromEnvironment(
    'ELP_FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _authDomain = String.fromEnvironment('ELP_FIREBASE_AUTH_DOMAIN');

  @override
  final bool isConfigured;

  @override
  String? get currentUid => isConfigured ? _currentFirebaseUid()?.toDart : null;

  @override
  final String? unavailableReason;

  static Future<WebFirebaseAuthAdapter> initialize() async {
    if (_project.isEmpty ||
        _apiKey.isEmpty ||
        _appId.isEmpty ||
        _senderId.isEmpty) {
      return WebFirebaseAuthAdapter._(
        isConfigured: false,
        unavailableReason: '尚未設定 Firebase Web App。',
      );
    }

    try {
      if (!(await _firebaseBridgeReady.toDart.timeout(
        const Duration(seconds: 4),
      )).toDart) {
        return WebFirebaseAuthAdapter._(
          isConfigured: false,
          unavailableReason: 'Firebase Web SDK 尚未載入；請確認網路連線。',
        );
      }
      final result = _decode(
        (await _initializeFirebaseAuth(
          jsonEncode({
            'apiKey': _apiKey,
            'authDomain': _authDomain.isEmpty
                ? '$_project.firebaseapp.com'
                : _authDomain,
            'projectId': _project,
            'appId': _appId,
            'messagingSenderId': _senderId,
          }).toJS,
        ).toDart).toDart,
      );
      final error = result['error'];
      if (error is String) {
        return WebFirebaseAuthAdapter._(
          isConfigured: false,
          unavailableReason: _messageFor(error),
        );
      }
      return WebFirebaseAuthAdapter._(isConfigured: true);
    } catch (_) {
      return WebFirebaseAuthAdapter._(
        isConfigured: false,
        unavailableReason: 'Firebase 登入服務暫時無法使用。',
      );
    }
  }

  @override
  Future<String?> signInWithGoogle() async {
    _requireConfigured();
    final result = _decode((await _signInWithGoogle().toDart).toDart);
    final uid = result['uid'];
    if (uid is String && uid.isNotEmpty) {
      return uid;
    }
    final code = result['error'];
    if (code == 'auth/popup-closed-by-user' ||
        code == 'auth/cancelled-popup-request') {
      return null;
    }
    throw WebFirebaseAuthException(code is String ? code : 'auth/unknown');
  }

  @override
  Future<void> signOut() async {
    _requireConfigured();
    final result = _decode((await _signOutFirebase().toDart).toDart);
    if (result['error'] case final String error) {
      throw WebFirebaseAuthException(error);
    }
  }

  @override
  Future<String> tokenFor(String expectedUid) async {
    _requireConfigured();
    if (currentUid != expectedUid) {
      throw const WebFirebaseAuthException('auth/user-mismatch');
    }
    final result = _decode(
      (await _firebaseIdToken(expectedUid.toJS).toDart).toDart,
    );
    if (result['uid'] != expectedUid || result['token'] is! String) {
      final code = result['error'];
      throw WebFirebaseAuthException(
        code is String ? code : 'auth/user-mismatch',
      );
    }
    return result['token'] as String;
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw StateError(
        unavailableReason ?? 'Firebase Web Auth is unavailable.',
      );
    }
  }

  static Map<String, Object?> _decode(String value) =>
      jsonDecode(value) as Map<String, Object?>;

  static String _messageFor(String code) => switch (code) {
    'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
    'auth/operation-not-allowed' => 'Firebase 尚未啟用 Google 登入。',
    _ => 'Firebase 登入服務暫時無法使用。',
  };
}

@JS('elpFirebaseAuthBridgeReady')
external JSPromise<JSBoolean> get _firebaseBridgeReady;

@JS('elpFirebaseAuthInitialize')
external JSPromise<JSString> _initializeFirebaseAuth(JSString optionsJson);

@JS('elpFirebaseAuthSignInWithGoogle')
external JSPromise<JSString> _signInWithGoogle();

@JS('elpFirebaseAuthSignOut')
external JSPromise<JSString> _signOutFirebase();

@JS('elpFirebaseAuthGetIdToken')
external JSPromise<JSString> _firebaseIdToken(JSString expectedUid);

@JS('elpFirebaseAuthCurrentUid')
external JSString? _currentFirebaseUid();
