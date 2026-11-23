import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/web_library_page.dart';
import 'core/audio/audio_engine_provider.dart';
import 'core/audio/audio_media_session_port.dart';
import 'core/audio/audio_media_session_provider.dart';
import 'core/audio/just_audio_adapter.dart';
import 'core/db/account_database_providers.dart';
import 'features/auth/web/web_firebase_auth_adapter.dart';
import 'features/auth/web/web_firebase_session_controller.dart';
import 'features/player/player_view_model.dart';
import 'features/auth/web/web_account_page.dart';
import 'features/sync/widgets/sync_landing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final webAuth = await WebFirebaseAuthAdapter.initialize();
  final engine = JustAudioAdapter();
  runApp(
    ProviderScope(
      overrides: [
        webFirebaseAuthPortProvider.overrideWithValue(webAuth),
        accountScopeProvider.overrideWith(
          (ref) => ref.watch(webAccountScopeProvider),
        ),
        webBeforeAccountChangeProvider.overrideWith(
          (ref) =>
              () => ref
                  .read(playerViewModelProvider.notifier)
                  .closeForAccountChange(),
        ),
        audioEngineProvider.overrideWith((ref) {
          ref.onDispose(() => unawaited(engine.dispose()));
          return engine;
        }),
        audioMediaSessionProvider.overrideWith(
          (ref) async => const NoopAudioMediaSession(),
        ),
      ],
      child: const EnglishLearningWebApp(),
    ),
  );
}

final class EnglishLearningWebApp extends ConsumerWidget {
  const EnglishLearningWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(
      webFirebaseSessionProvider.select((state) => state.uid),
    );
    return MaterialApp(
      key: ValueKey(uid),
      title: 'English Learning Player',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: SyncLanding(
        uid: uid,
        library: const WebLibraryPage(),
        accountPage: const WebAccountPage(),
      ),
    );
  }
}
