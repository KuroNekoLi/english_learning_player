import 'package:english_learning_player/core/db/account_database_providers.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/features/sync/firebase_sync_dependencies.dart';
import 'package:english_learning_player/features/sync/sync_preference.dart';
import 'package:english_learning_player/features/sync/widgets/sync_consent_controls.dart';
import 'package:english_learning_player/features/sync/widgets/sync_landing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_sync_preference.dart';

void main() {
  testWidgets('launches an automatic pass only after the first opt-in', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final storage = FakeSyncPreferencePersistence();
    var runs = 0;
    const key = (uid: 'alice', project: 'example-project');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountScopeProvider.overrideWithValue(AccountScope(key.uid)),
          syncPreferenceStoreProvider.overrideWith((ref) async => storage),
          firebaseMediaEndpointProvider.overrideWithValue(
            FirebaseEndpoint(
              project: key.project,
              apiKey: 'test',
              bucket: 'example-project.firebasestorage.app',
            ),
          ),
          firebaseSyncRuntimeProvider.overrideWith((ref) async {
            runs++;
            return null;
          }),
        ],
        child: MaterialApp(
          home: SyncLanding(
            uid: key.uid,
            library: const Scaffold(body: Text('教材庫')),
            accountPage: Scaffold(
              body: SyncConsentControls(
                preferenceKey: key,
                busy: false,
                onSync: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('開啟同步'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(runs, 0);
    await tester.tap(find.text('開啟同步'));
    await tester.pumpAndSettle();
    expect(storage.choices[key], SyncPreference.enabled);
    expect(find.text('教材庫'), findsOneWidget);
    expect(runs, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
