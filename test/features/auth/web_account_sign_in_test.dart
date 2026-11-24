import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/account_database_providers.dart';
import 'package:english_learning_player/features/sync/sync_preference.dart';
import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/auth/web/web_account_page.dart';
import 'package:english_learning_player/features/auth/web/web_firebase_auth_port.dart';
import 'package:english_learning_player/features/auth/web/web_firebase_session_controller.dart';
import 'package:english_learning_player/features/sync/firebase_sync_dependencies.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_sync_preference.dart';

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
      throwsA(isA<SyncFailure>()),
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

  testWidgets('remembers enable and later separately for each account', (
    tester,
  ) async {
    final preferences = FakeSyncPreferencePersistence();
    final auth = _FakeWebFirebaseAuthPort()..currentUid = 'google-user-a';
    final container = ProviderContainer(
      overrides: [
        webFirebaseAuthPortProvider.overrideWithValue(auth),
        accountScopeProvider.overrideWith(
          (ref) => ref.watch(webAccountScopeProvider),
        ),
        syncPreferenceStoreProvider.overrideWith((ref) async => preferences),
        firebaseMediaEndpointProvider.overrideWithValue(
          FirebaseEndpoint(
            project: 'example-project',
            apiKey: 'fixture-key',
            bucket: 'example-project.firebasestorage.app',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.pumpAndSettle();
    final syncButton = find.widgetWithText(FilledButton, '立即同步');
    expect(syncButton, findsNothing);
    await tester.tap(find.text('開啟同步'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(syncButton).onPressed, isNotNull);

    Future<void> signInAgain(String uid) async {
      await tester.tap(find.byKey(const ValueKey('webSignOut')));
      await tester.pumpAndSettle();
      auth.nextUid = uid;
      await tester.tap(find.byKey(const ValueKey('webGoogleSignIn')));
      await tester.pumpAndSettle();
    }

    await signInAgain('google-user-b');
    expect(find.text('開啟同步'), findsOneWidget);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(syncButton).onPressed, isNull);
    await signInAgain('google-user-a');
    expect(find.text('開啟同步'), findsNothing);
    expect(tester.widget<FilledButton>(syncButton).onPressed, isNotNull);
    await signInAgain('google-user-b');
    expect(find.text('開啟同步'), findsNothing);
    expect(tester.widget<FilledButton>(syncButton).onPressed, isNull);
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

  testWidgets('username login scopes a separate local read-only profile', (
    tester,
  ) async {
    final auth = _FakeWebFirebaseAuthPort()..nextUid = 'shared-owner-uid';
    final preferences = FakeSyncPreferencePersistence();
    final container = ProviderContainer(
      overrides: [
        webFirebaseAuthPortProvider.overrideWithValue(auth),
        accountScopeProvider.overrideWith(
          (ref) => ref.watch(webAccountScopeProvider),
        ),
        firebaseMediaEndpointProvider.overrideWithValue(
          FirebaseEndpoint(
            project: 'example-project',
            apiKey: 'test-only',
            bucket: 'example-project.firebasestorage.app',
          ),
        ),
        syncPreferenceStoreProvider.overrideWith((ref) async => preferences),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));

    await tester.tap(find.byKey(const ValueKey('webUsernamePasswordSignIn')));
    await tester.pumpAndSettle();
    expect(find.text('帳號密碼登入（唯讀）'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('usernameLoginPassword')),
      'not-a-real-password',
    );
    await tester.tap(find.byKey(const ValueKey('usernameLoginSubmit')));
    await tester.pumpAndSettle();

    expect(auth.usernameSignIns, 1);
    expect(container.read(webFirebaseSessionProvider).readOnly, isTrue);
    expect(
      container.read(webAccountScopeProvider).ownerId,
      'shared-owner-uid:password-reader',
    );
    expect(
      container.read(webAccountScopeProvider).cloudUid,
      'shared-owner-uid',
    );
    expect(find.text('帳號密碼登入：唯讀'), findsOneWidget);
    await tester.tap(find.text('開啟自動下載'));
    await tester.pumpAndSettle();
    expect(find.text('自動下載音檔與字幕'), findsOneWidget);
    expect(find.text('立即更新與下載'), findsOneWidget);
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
  bool isReadOnly = false;
  @override
  String? unavailableReason;
  String? nextUid = 'google-user-a';
  WebFirebaseAuthException? nextError;
  int signInCalls = 0;
  int usernameSignIns = 0;
  int signOutCalls = 0;

  @override
  Future<String?> signInWithGoogle() async {
    signInCalls++;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    currentUid = nextUid;
    isReadOnly = false;
    return currentUid;
  }

  @override
  Future<String?> signInWithUsername(String username, String password) async {
    usernameSignIns++;
    currentUid = nextUid ?? 'password-user';
    isReadOnly = true;
    return currentUid;
  }

  @override
  Future<void> linkReadOnlyUsername(String username, String password) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUid = null;
    isReadOnly = false;
  }

  @override
  Future<String> tokenFor(String expectedUid) async {
    if (currentUid != expectedUid) {
      throw const WebFirebaseAuthException('auth/user-mismatch');
    }
    return 'fresh-firebase-id-token';
  }
}
