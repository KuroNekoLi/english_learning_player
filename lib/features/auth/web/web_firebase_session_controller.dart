import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/sync/sync_contracts.dart';
import '../data/firebase_identity_session.dart';
import 'web_firebase_auth_port.dart';

final webFirebaseAuthPortProvider = Provider<WebFirebaseAuthPort>(
  (ref) => _UnavailableWebFirebaseAuthPort(),
);

/// Invoked before changing the UID that scopes local repositories.
final webBeforeAccountChangeProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

typedef WebFirebaseSessionState = ({
  String? uid,
  bool busy,
  String? message,
  bool readOnly,
});

final webFirebaseSessionProvider =
    NotifierProvider<WebFirebaseSessionController, WebFirebaseSessionState>(
      WebFirebaseSessionController.new,
    );

final webFirebaseIdentitySessionProvider = Provider<FirebaseIdentitySession>((
  ref,
) {
  final port = ref.watch(webFirebaseAuthPortProvider);
  final state = ref.watch(webFirebaseSessionProvider);
  return _WebFirebaseIdentitySession(port, state.uid, state.readOnly);
});

final webAccountScopeProvider = Provider<AccountScope>((ref) {
  final state = ref.watch(webFirebaseSessionProvider);
  final uid = state.uid;
  if (uid == null) return AccountScope('local-default');
  return AccountScope(
    state.readOnly ? '$uid:password-reader' : uid,
    cloudUid: uid,
  );
});

final class WebFirebaseSessionController
    extends Notifier<WebFirebaseSessionState> {
  @override
  WebFirebaseSessionState build() => (
    uid: ref.watch(webFirebaseAuthPortProvider).currentUid,
    busy: false,
    message: null,
    readOnly: ref.watch(webFirebaseAuthPortProvider).isReadOnly,
  );

  Future<void> signInWithGoogle() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid != null) return;
    if (!port.isConfigured) {
      state = (
        uid: null,
        busy: false,
        message: port.unavailableReason ?? 'Firebase Web Auth 尚未設定。',
        readOnly: false,
      );
      return;
    }
    state = (uid: null, busy: true, message: null, readOnly: false);
    try {
      final uid = await port.signInWithGoogle();
      if (!ref.mounted) return;
      if (uid == null) {
        state = (uid: null, busy: false, message: null, readOnly: false);
        return;
      }
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      state = (uid: uid, busy: false, message: null, readOnly: port.isReadOnly);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (
        uid: null,
        busy: false,
        message: _messageFor(error.code),
        readOnly: false,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = (
        uid: null,
        busy: false,
        message: 'Google 登入失敗，請稍後重試。',
        readOnly: false,
      );
    }
  }

  Future<void> signInWithUsername(String username, String password) async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid != null) return;
    if (!port.isConfigured) throw StateError('Firebase Web Auth 尚未設定。');
    state = (uid: null, busy: true, message: null, readOnly: false);
    try {
      final uid = await port.signInWithUsername(username, password);
      if (!ref.mounted || uid == null) return;
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      state = (uid: uid, busy: false, message: null, readOnly: port.isReadOnly);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (
        uid: null,
        busy: false,
        message: _messageFor(error.code),
        readOnly: false,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = (
        uid: null,
        busy: false,
        message: '帳號密碼登入失敗，請檢查資料後重試。',
        readOnly: false,
      );
    }
  }

  Future<void> linkReadOnlyUsername(String username, String password) async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid == null || state.readOnly) return;
    final previousUid = state.uid;
    state = (uid: previousUid, busy: true, message: null, readOnly: false);
    try {
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      await port.linkReadOnlyUsername(username, password);
      await port.signOut();
      if (!ref.mounted) return;
      state = (uid: null, busy: false, message: null, readOnly: false);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (
        uid: previousUid,
        busy: false,
        message: _messageFor(error.code),
        readOnly: false,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = (
        uid: previousUid,
        busy: false,
        message: '設定帳號密碼失敗，請稍後重試。',
        readOnly: false,
      );
    }
  }

  Future<void> signOut() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid == null) return;
    state = (
      uid: state.uid,
      busy: true,
      message: null,
      readOnly: state.readOnly,
    );
    try {
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      await port.signOut();
      if (!ref.mounted) return;
      state = (uid: null, busy: false, message: null, readOnly: false);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (
        uid: state.uid,
        busy: false,
        message: _messageFor(error.code),
        readOnly: state.readOnly,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = (
        uid: state.uid,
        busy: false,
        message: '登出失敗，請稍後重試。',
        readOnly: state.readOnly,
      );
    }
  }

  String _messageFor(String code) => switch (code) {
    'auth/popup-blocked' => '瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。',
    'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
    'auth/operation-not-allowed' => 'Firebase 尚未啟用此登入方式。',
    'auth/invalid-credential' ||
    'auth/invalid-login-credentials' => '帳號或密碼不正確。',
    'auth/network-request-failed' => '網路連線失敗，請確認連線後重試。',
    'auth/account-exists-with-different-credential' =>
      '這個電子郵件已使用其他登入方式，請使用原本的登入方式。',
    'auth/weak-password' => '密碼至少需要 12 個字元。',
    'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
    _ => 'Firebase 登入失敗，請稍後重試。',
  };
}

final class _WebFirebaseIdentitySession implements FirebaseIdentitySession {
  const _WebFirebaseIdentitySession(this._port, this.uid, this.isReadOnly);

  final WebFirebaseAuthPort _port;

  @override
  final String? uid;

  @override
  final bool isReadOnly;

  @override
  Future<SyncIdentity?> currentIdentity() async =>
      uid != null && _port.currentUid == uid ? SyncIdentity(uid!) : null;

  @override
  Future<String> tokenFor(String expectedUid) async {
    if (uid != expectedUid || _port.currentUid != uid) {
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'account_changed',
      );
    }
    try {
      return await _port.tokenFor(expectedUid);
    } on WebFirebaseAuthException catch (error) {
      throw SyncFailure(
        error.code == 'auth/network-request-failed'
            ? SyncFailureKind.transient
            : SyncFailureKind.unauthenticated,
        error.code,
      );
    }
  }
}

final class _UnavailableWebFirebaseAuthPort implements WebFirebaseAuthPort {
  @override
  bool get isConfigured => false;
  @override
  String? get currentUid => null;
  @override
  bool get isReadOnly => false;
  @override
  String? get unavailableReason => 'Firebase Web App 尚未初始化。';
  @override
  Future<String?> signInWithGoogle() => throw StateError(unavailableReason!);
  @override
  Future<String?> signInWithUsername(String username, String password) =>
      throw StateError(unavailableReason!);
  @override
  Future<void> linkReadOnlyUsername(String username, String password) =>
      throw StateError(unavailableReason!);
  @override
  Future<void> signOut() async => throw StateError(unavailableReason!);
  @override
  Future<String> tokenFor(String expectedUid) =>
      throw StateError(unavailableReason!);
}

String webAuthMessageFor(String code) => switch (code) {
  'auth/popup-blocked' => '瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。',
  'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
  'auth/operation-not-allowed' => 'Firebase 尚未啟用此登入方式。',
  'auth/invalid-credential' || 'auth/invalid-login-credentials' => '帳號或密碼不正確。',
  'auth/network-request-failed' => '網路連線失敗，請確認連線後重試。',
  'auth/weak-password' => '密碼至少需要 12 個字元。',
  'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
  _ => 'Firebase 登入失敗，請稍後重試。',
};
