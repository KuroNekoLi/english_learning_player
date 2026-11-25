import 'dart:async';

import 'package:audio_service/audio_service.dart' as service;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_engine_provider.dart';
import 'core/audio/audio_media_session_port.dart';
import 'core/audio/audio_media_session_provider.dart';
import 'core/audio/english_audio_handler.dart';
import 'core/audio/just_audio_adapter.dart';
import 'app/library_page.dart';
import 'core/db/account_scope.dart';
import 'core/db/account_database_providers.dart';
import 'features/auth/firebase_session_controller.dart';
import 'features/auth/data/secure_firebase_credential_store.dart';
import 'features/auth/social_sign_in.dart';
import 'features/player/player_view_model.dart';
import 'features/sync/firebase_sync_panel.dart';
import 'features/sync/widgets/sync_landing.dart';

const audioServiceConfig = service.AudioServiceConfig(
  androidNotificationChannelId: 'com.linli.englishlearningplayer.audio',
  androidNotificationChannelName: 'English Learning Player',
  androidNotificationOngoing: false,
  androidStopForegroundOnPause: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = JustAudioAdapter();
  EnglishAudioHandler? handler;
  final candidateHandler = EnglishAudioHandler(engine);
  try {
    handler = await service.AudioService.init<EnglishAudioHandler>(
      builder: () => candidateHandler,
      config: audioServiceConfig,
    );
  } catch (_) {
    await candidateHandler.close();
  }
  final container = ProviderContainer(
    overrides: [
      firebaseCredentialStoreProvider.overrideWithValue(
        SecureFirebaseCredentialStore(),
      ),
      beforeAccountChangeProvider.overrideWith(
        (ref) =>
            () => ref
                .read(playerViewModelProvider.notifier)
                .closeForAccountChange(),
      ),
      accountScopeProvider.overrideWith((ref) {
        final session = ref.watch(firebaseSessionProvider);
        final uid = session.uid;
        if (uid == null) return AccountScope('local-default');
        return AccountScope(uid, cloudUid: session.cloudUid ?? uid);
      }),
      audioEngineProvider.overrideWith((ref) {
        ref.onDispose(() => unawaited(engine.dispose()));
        return engine;
      }),
      audioMediaSessionProvider.overrideWith((ref) {
        final mediaSession = handler ?? const NoopAudioMediaSession();
        if (handler case final currentHandler?) {
          ref.onDispose(() => unawaited(currentHandler.close()));
        }
        return Future.value(mediaSession);
      }),
    ],
  );
  final session = container.read(firebaseAuthSessionProvider);
  try {
    final socialSignIn = container.read(socialSignInProvider);
    final nativeUser = await socialSignIn?.restore(SocialProvider.apple);
    await session?.restore(
      nativeUser: nativeUser is NativeFirebaseUser ? nativeUser : null,
    );
  } catch (_) {
    // Keep the offline library available if secure storage is temporarily
    // unavailable. The account can still be restored on a later launch.
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const EnglishLearningPlayer(),
    ),
  );
}

class EnglishLearningPlayer extends ConsumerWidget {
  const EnglishLearningPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseSessionProvider.select((state) => state.uid));
    return MaterialApp(
      key: ValueKey(uid),
      title: 'English Learning Player',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: SyncLanding(
        uid: uid,
        library: const LibraryPage(),
        accountPage: const FirebaseSyncPanel(),
      ),
    );
  }
}
