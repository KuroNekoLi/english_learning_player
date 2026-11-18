import 'dart:async';

import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/auth/social_sign_in.dart';
import 'package:english_learning_player/features/sync/data/firebase_endpoint.dart';
import 'package:english_learning_player/features/sync/firebase_sync_dependencies.dart';
import 'package:english_learning_player/features/sync/firebase_sync_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows disabled social buttons in an unconfigured build', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: FirebaseSyncPanel())),
    );
    expect(find.textContaining('尚未設定的登入方式'), findsOneWidget);
    expect(find.text('使用測試帳號'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'routes both social buttons and clears UID and consent on logout',
    (tester) async {
      final social = _FakeSocialSignIn();
      final container = ProviderContainer(
        overrides: [
          firebaseEndpointProvider.overrideWithValue(
            FirebaseEndpoint(
              project: 'example-project',
              bucket: 'example-project.appspot.com',
              apiKey: 'test-only',
            ),
          ),
          socialSignInProvider.overrideWithValue(social),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: FirebaseSyncPanel()),
        ),
      );

      final signedIn = Completer<SocialSignInResult?>();
      social.result = signedIn.future;
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(social.attempts, [SocialProvider.google]);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      signedIn.complete(null);
      await tester.pumpAndSettle();
      expect(container.read(firebaseSessionProvider).uid, isNull);

      social.result = Future.value(
        NativeFirebaseUser('apple-uid', () async => 'test-firebase-token'),
      );
      await tester.tap(find.byKey(const ValueKey('appleSignIn')));
      await tester.pumpAndSettle();
      expect(social.attempts, [SocialProvider.google, SocialProvider.apple]);
      expect(container.read(firebaseSessionProvider), (
        uid: 'apple-uid',
        consent: false,
      ));

      final session = container.read(firebaseAuthSessionProvider)!;
      expect(await session.tokenFor('apple-uid'), 'test-firebase-token');
      await expectLater(
        session.tokenFor('other-uid'),
        throwsA(isA<SyncFailure>()),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(container.read(firebaseSessionProvider).consent, isTrue);

      await tester.tap(find.text('登出'));
      await tester.pumpAndSettle();
      expect(container.read(firebaseSessionProvider), (
        uid: null,
        consent: false,
      ));
      expect(await session.currentIdentity(), isNull);
      expect(social.signOuts, [SocialProvider.apple]);
      await expectLater(
        session.tokenFor('apple-uid'),
        throwsA(isA<SyncFailure>()),
      );
    },
  );

  testWidgets('shows login errors and lets the user try again', (tester) async {
    final social = _FakeSocialSignIn();
    final container = ProviderContainer(
      overrides: [
        firebaseEndpointProvider.overrideWithValue(
          FirebaseEndpoint(
            project: 'example-project',
            bucket: 'example-project.appspot.com',
            apiKey: 'test-only',
          ),
        ),
        socialSignInProvider.overrideWithValue(social),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FirebaseSyncPanel()),
      ),
    );
    final failed = Completer<SocialSignInResult?>();
    social.result = failed.future;
    await tester.tap(find.byKey(const ValueKey('appleSignIn')));
    failed.completeError(
      const SyncFailure(
        SyncFailureKind.unauthenticated,
        'sign_in_account_link_required',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('請使用原本的登入方式'), findsOneWidget);
    expect(container.read(firebaseSessionProvider).uid, isNull);

    social.result = Future.value(null);
    await tester.tap(find.byKey(const ValueKey('appleSignIn')));
    await tester.pumpAndSettle();
    expect(social.attempts, [SocialProvider.apple, SocialProvider.apple]);
    expect(find.textContaining('請使用原本的登入方式'), findsNothing);
  });
}

final class _FakeSocialSignIn implements SocialSignIn {
  Future<SocialSignInResult?>? result;
  final attempts = <SocialProvider>[];
  final signOuts = <SocialProvider>[];

  @override
  bool isConfigured(SocialProvider provider) => true;

  @override
  Future<SocialSignInResult?> signIn(SocialProvider provider) async {
    attempts.add(provider);
    return result;
  }

  @override
  Future<void> signOut(SocialProvider provider) async => signOuts.add(provider);
}
