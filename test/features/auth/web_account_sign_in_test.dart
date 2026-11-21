import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/features/auth/web/web_account_page.dart';
import 'package:english_learning_player/features/auth/web/web_firebase_auth_port.dart';
import 'package:english_learning_player/features/auth/web/web_firebase_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('canceled popup keeps the offline account scope', (tester) async {
    final auth = _FakeWebFirebaseAuthPort()..nextUid = null;
    final container = _container(auth);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(container.read(webFirebaseSessionProvider).uid, isNull);
    expect(container.read(webAccountScopeProvider).ownerId, 'local-default');
    expect(find.text('登入同步帳號'), findsOneWidget);
  });

  testWidgets('Google login scopes data and logout restores offline library', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort();
    var boundaryCalls = 0;
    final container = _container(
      auth,
      beforeAccountChange: () async => boundaryCalls++,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();

    expect(container.read(webFirebaseSessionProvider).uid, 'google-user-a');
    expect(container.read(webAccountScopeProvider).ownerId, 'google-user-a');
    expect(
      container.read(webAccountScopeProvider).storageKey,
      isNot(AccountScope('local-default').storageKey),
    );
    expect(boundaryCalls, 1);
    expect(find.byKey(const ValueKey('webSignOut')), findsOneWidget);

    final session = container.read(webFirebaseIdentitySessionProvider);
    expect((await session.currentIdentity())?.uid, 'google-user-a');
    expect(await session.tokenFor('google-user-a'), 'fresh-firebase-id-token');
    await expectLater(
      session.tokenFor('google-user-b'),
      throwsA(isA<WebFirebaseAuthException>()),
    );

    await tester.tap(find.byKey(const ValueKey('webSignOut')));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(container.read(webFirebaseSessionProvider).uid, isNull);
    expect(container.read(webAccountScopeProvider).ownerId, 'local-default');
    expect(boundaryCalls, 2);
  });

  testWidgets('supports choosing another Google account after logout', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort();
    final container = _container(auth);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();
    expect(container.read(webAccountScopeProvider).ownerId, 'google-user-a');

    await tester.tap(find.byKey(const ValueKey('webSignOut')));
    await tester.pumpAndSettle();
    auth.nextUid = 'google-user-b';
    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();

    expect(container.read(webFirebaseSessionProvider).uid, 'google-user-b');
    expect(container.read(webAccountScopeProvider).ownerId, 'google-user-b');
    expect(auth.signInCalls, 2);
  });

  testWidgets('shows popup and authorization failures without changing scope', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort()
      ..nextError = const WebFirebaseAuthException('auth/popup-blocked');
    final container = _container(auth);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();
    expect(find.text('瀏覽器封鎖登入視窗，請允許此網站開啟彈出式視窗。'), findsOneWidget);
    expect(container.read(webAccountScopeProvider).ownerId, 'local-default');

    auth.nextError = const WebFirebaseAuthException('auth/unauthorized-domain');
    await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
    await tester.pumpAndSettle();
    expect(find.text('目前網址尚未加入 Firebase 授權網域。'), findsOneWidget);
    expect(container.read(webFirebaseSessionProvider).uid, isNull);
  });

  testWidgets('restores the persisted Firebase UID when app starts', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort()..currentUid = 'restored-user';
    final container = _container(auth);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    expect(container.read(webAccountScopeProvider).ownerId, 'restored-user');
    expect(find.byKey(const ValueKey('webSignOut')), findsOneWidget);
  });

  testWidgets('disables Google sign in when Web config is unavailable', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort()
      ..isConfigured = false
      ..unavailableReason = '尚未設定 Firebase Web App。';
    final container = _container(auth);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('webGoogleSignIn')))
          .onPressed,
      isNull,
    );
    expect(find.text('尚未設定 Firebase Web App。'), findsOneWidget);
  });
}

ProviderContainer _container(
  _FakeWebFirebaseAuthPort auth, {
  Future<void> Function()? beforeAccountChange,
}) => ProviderContainer(
  overrides: [
    webFirebaseAuthPortProvider.overrideWithValue(auth),
    if (beforeAccountChange != null)
      webBeforeAccountChangeProvider.overrideWithValue(beforeAccountChange),
  ],
);

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: WebAccountPage()),
);

final class _FakeWebFirebaseAuthPort implements WebFirebaseAuthPort {
  @override
  bool isConfigured = true;
  @override
  String? currentUid;
  @override
  String? unavailableReason;
  String? nextUid = 'google-user-a';
  WebFirebaseAuthException? nextError;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> signInWithGoogle() async {
    signInCalls++;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    currentUid = nextUid;
    return currentUid;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUid = null;
  }

  @override
  Future<String> tokenFor(String expectedUid) async {
    if (currentUid != expectedUid) {
      throw const WebFirebaseAuthException('auth/user-mismatch');
    }
    return 'fresh-firebase-id-token';
  }
}
