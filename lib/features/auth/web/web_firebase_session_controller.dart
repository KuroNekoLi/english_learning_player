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
  String? cloudUid,
  bool busy,
  String? message,
  bool readOnly,
  bool canProvisionReadOnlyLogin,
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
  return _WebFirebaseIdentitySession(
    port,
    state.uid,
    state.cloudUid ?? state.uid,
    state.readOnly,
  );
});

final webAccountScopeProvider = Provider<AccountScope>((ref) {
  final state = ref.watch(webFirebaseSessionProvider);
  final uid = state.uid;
  if (uid == null) return AccountScope('local-default');
  return AccountScope(uid, cloudUid: state.cloudUid ?? uid);
});

final class WebFirebaseSessionController
    extends Notifier<WebFirebaseSessionState> {
  @override
  WebFirebaseSessionState build() {
    final port = ref.watch(webFirebaseAuthPortProvider);
    final uid = port.currentUid;
    return (
      uid: uid,
      cloudUid: port.cloudUid ?? uid,
      busy: false,
      message: null,
      readOnly: port.isReadOnly,
      canProvisionReadOnlyLogin: port.canProvisionReadOnlyLogin,
    );
  }

  Future<void> signInWithGoogle() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid != null) return;
    if (!port.isConfigured) {
      state = _empty(
        message: port.unavailableReason ?? 'Firebase Web Auth 尚未設定。',
      );
      return;
    }
    state = _empty(busy: true);
    try {
      final uid = await port.signInWithGoogle();
      if (!ref.mounted) return;
      if (uid == null) {
        state = _empty();
        return;
      }
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      state = _signedIn(port, uid);
    } on WebFirebaseAuthException catch (error) {
      if (ref.mounted) state = _empty(message: _messageFor(error.code));
    } catch (_) {
      if (ref.mounted) state = _empty(message: 'Google 登入失敗，請稍後重試。');
    }
  }

  Future<void> signInWithUsername(String username, String password) async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid != null) return;
    if (!port.isConfigured) throw StateError('Firebase Web Auth 尚未設定。');
    state = _empty(busy: true);
    try {
      final uid = await port.signInWithUsername(username, password);
      if (!ref.mounted || uid == null) return;
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      state = _signedIn(port, uid);
    } on WebFirebaseAuthException catch (error) {
      if (ref.mounted) state = _empty(message: _messageFor(error.code));
    } catch (_) {
      if (ref.mounted) state = _empty(message: '帳號密碼登入失敗，請檢查資料後重試。');
    }
  }

  Future<String?> provisionReadOnlyLogin(
    String username,
    String password,
  ) async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid == null || !state.canProvisionReadOnlyLogin) {
      return null;
    }
    final previous = state;
    state = (
      uid: previous.uid,
      cloudUid: previous.cloudUid,
      busy: true,
      message: null,
      readOnly: previous.readOnly,
      canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
    );
    try {
      final readerUid = await port.provisionReadOnlyLogin(username, password);
      if (!ref.mounted) return readerUid;
      state = (
        uid: previous.uid,
        cloudUid: previous.cloudUid,
        busy: false,
        message: '唯讀帳號已設定；登出後即可用帳號密碼登入。',
        readOnly: previous.readOnly,
        canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
      );
      return readerUid;
    } on WebFirebaseAuthException catch (error) {
      if (ref.mounted) {
        state = (
          uid: previous.uid,
          cloudUid: previous.cloudUid,
          busy: false,
          message: _messageFor(error.code),
          readOnly: previous.readOnly,
          canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = (
          uid: previous.uid,
          cloudUid: previous.cloudUid,
          busy: false,
          message: '設定帳號密碼失敗，請稍後重試。',
          readOnly: previous.readOnly,
          canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
        );
      }
    }
    return null;
  }

  Future<void> signOut() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid == null) return;
    final previous = state;
    state = (
      uid: previous.uid,
      cloudUid: previous.cloudUid,
      busy: true,
      message: null,
      readOnly: previous.readOnly,
      canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
    );
    try {
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      await port.signOut();
      if (ref.mounted) state = _empty();
    } on WebFirebaseAuthException catch (error) {
      if (ref.mounted) {
        state = (
          uid: previous.uid,
          cloudUid: previous.cloudUid,
          busy: false,
          message: _messageFor(error.code),
          readOnly: previous.readOnly,
          canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = (
          uid: previous.uid,
          cloudUid: previous.cloudUid,
          busy: false,
          message: '登出失敗，請稍後重試。',
          readOnly: previous.readOnly,
          canProvisionReadOnlyLogin: previous.canProvisionReadOnlyLogin,
        );
      }
    }
  }

  WebFirebaseSessionState _empty({bool busy = false, String? message}) => (
    uid: null,
    cloudUid: null,
    busy: busy,
    message: message,
    readOnly: false,
    canProvisionReadOnlyLogin: false,
  );

  WebFirebaseSessionState _signedIn(WebFirebaseAuthPort port, String uid) => (
    uid: uid,
    cloudUid: port.cloudUid ?? uid,
    busy: false,
    message: null,
    readOnly: port.isReadOnly,
    canProvisionReadOnlyLogin: port.canProvisionReadOnlyLogin,
  );

  String _messageFor(String code) => switch (code) {
    'auth/popup-blocked' => '瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。',
    'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
    'auth/operation-not-allowed' => 'Firebase 尚未啟用此登入方式。',
    'auth/invalid-credential' ||
    'auth/invalid-login-credentials' => '帳號或密碼不正確。',
    'auth/network-request-failed' => '網路連線失敗，請確認連線後重試。',
    'auth/weak-password' => '密碼未符合 Firebase 專案的密碼政策。',
    'auth/permission-denied' => '目前 Google 帳號尚未獲准設定唯讀登入。',
    'auth/email-already-in-use' => '此測試帳號已被其他 Firebase 使用者使用。',
    'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
    _ => 'Firebase 登入失敗，請稍後重試。',
  };
}

final class _WebFirebaseIdentitySession implements FirebaseIdentitySession {
  const _WebFirebaseIdentitySession(
    this._port,
    this.uid,
    this.cloudUid,
    this.isReadOnly,
  );

  final WebFirebaseAuthPort _port;

  @override
  final String? uid;

  @override
  final String? cloudUid;

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
  String? get cloudUid => null;
  @override
  bool get isReadOnly => false;
  @override
  bool get canProvisionReadOnlyLogin => false;
  @override
  String? get unavailableReason => 'Firebase Web App 尚未初始化。';
  @override
  Future<String?> signInWithGoogle() => throw StateError(unavailableReason!);
  @override
  Future<String?> signInWithUsername(String username, String password) =>
      throw StateError(unavailableReason!);
  @override
  Future<String> provisionReadOnlyLogin(String username, String password) =>
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
  'auth/weak-password' => '密碼未符合 Firebase 專案的密碼政策。',
  'auth/permission-denied' => '目前 Google 帳號尚未獲准設定唯讀登入。',
  'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
  _ => 'Firebase 登入失敗，請稍後重試。',
};
