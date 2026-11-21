import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/sync/sync_identity.dart';
import '../data/firebase_identity_session.dart';
import 'web_firebase_auth_port.dart';

final webFirebaseAuthPortProvider = Provider<WebFirebaseAuthPort>(
  (ref) => _UnavailableWebFirebaseAuthPort(),
);

/// Invoked before changing the UID that scopes local repositories.
final webBeforeAccountChangeProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

typedef WebFirebaseSessionState = ({String? uid, bool busy, String? message});

final webFirebaseSessionProvider =
    NotifierProvider<WebFirebaseSessionController, WebFirebaseSessionState>(
      WebFirebaseSessionController.new,
    );

/// The same UID-scoped contract consumed by Firebase sync transports.
final webFirebaseIdentitySessionProvider = Provider<FirebaseIdentitySession>((
  ref,
) {
  final port = ref.watch(webFirebaseAuthPortProvider);
  final uid = ref.watch(
    webFirebaseSessionProvider.select((state) => state.uid),
  );
  return _WebFirebaseIdentitySession(port, uid);
});

/// Use Firebase UID only; signed-out data remains in its offline scope.
final webAccountScopeProvider = Provider<AccountScope>((ref) {
  final uid = ref.watch(
    webFirebaseSessionProvider.select((state) => state.uid),
  );
  return AccountScope(uid ?? 'local-default');
});

final class WebFirebaseSessionController
    extends Notifier<WebFirebaseSessionState> {
  @override
  WebFirebaseSessionState build() => (
    uid: ref.watch(webFirebaseAuthPortProvider).currentUid,
    busy: false,
    message: null,
  );

  Future<void> signInWithGoogle() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid != null) return;
    if (!port.isConfigured) {
      state = (
        uid: null,
        busy: false,
        message: port.unavailableReason ?? 'Firebase Web Auth 尚未設定。',
      );
      return;
    }

    state = (uid: null, busy: true, message: null);
    try {
      // Call immediately from the button callback so the browser permits popup.
      final uid = await port.signInWithGoogle();
      if (!ref.mounted) return;
      if (uid == null) {
        state = (uid: null, busy: false, message: null);
        return;
      }
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      state = (uid: uid, busy: false, message: null);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (uid: null, busy: false, message: _messageFor(error.code));
    } catch (_) {
      if (!ref.mounted) return;
      state = (uid: null, busy: false, message: 'Google 登入失敗，請稍後重試。');
    }
  }

  Future<void> signOut() async {
    final port = ref.read(webFirebaseAuthPortProvider);
    if (state.busy || state.uid == null) return;
    state = (uid: state.uid, busy: true, message: null);
    try {
      await ref.read(webBeforeAccountChangeProvider)();
      if (!ref.mounted) return;
      await port.signOut();
      if (!ref.mounted) return;
      state = (uid: null, busy: false, message: null);
    } on WebFirebaseAuthException catch (error) {
      if (!ref.mounted) return;
      state = (uid: state.uid, busy: false, message: _messageFor(error.code));
    } catch (_) {
      if (!ref.mounted) return;
      state = (uid: state.uid, busy: false, message: '登出失敗，請稍後重試。');
    }
  }

  String _messageFor(String code) => switch (code) {
    'auth/popup-blocked' => '瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。',
    'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
    'auth/operation-not-allowed' => 'Firebase 尚未啟用 Google 登入。',
    'auth/network-request-failed' => '網路連線失敗，請確認連線後重試。',
    'auth/account-exists-with-different-credential' =>
      '這個電子郵件已使用其他登入方式，請使用原本的登入方式。',
    'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
    _ => 'Google 登入失敗，請稍後重試。',
  };
}

final class _WebFirebaseIdentitySession implements FirebaseIdentitySession {
  const _WebFirebaseIdentitySession(this._port, this.uid);

  final WebFirebaseAuthPort _port;

  @override
  final String? uid;

  @override
  Future<SyncIdentity?> currentIdentity() async =>
      uid == null ? null : SyncIdentity(uid!);

  @override
  Future<String> tokenFor(String expectedUid) {
    if (uid != expectedUid) {
      return Future.error(const WebFirebaseAuthException('auth/user-mismatch'));
    }
    return _port.tokenFor(expectedUid);
  }
}

final class _UnavailableWebFirebaseAuthPort implements WebFirebaseAuthPort {
  @override
  bool get isConfigured => false;

  @override
  String? get currentUid => null;

  @override
  String? get unavailableReason => 'Firebase Web App 尚未初始化。';

  @override
  Future<String?> signInWithGoogle() => throw StateError(unavailableReason!);

  @override
  Future<void> signOut() async => throw StateError(unavailableReason!);

  @override
  Future<String> tokenFor(String expectedUid) =>
      throw StateError(unavailableReason!);
}

String webAuthMessageFor(String code) => switch (code) {
  'auth/popup-blocked' => '瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。',
  'auth/unauthorized-domain' => '目前網址尚未加入 Firebase 授權網域。',
  'auth/operation-not-allowed' => 'Firebase 尚未啟用 Google 登入。',
  'auth/network-request-failed' => '網路連線失敗，請確認連線後重試。',
  'auth/account-exists-with-different-credential' =>
    '這個電子郵件已使用其他登入方式，請使用原本的登入方式。',
  'auth/invalid-api-key' => 'Firebase Web App 設定無效。',
  _ => 'Google 登入失敗，請稍後重試。',
};
