import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/web_library_page.dart';
import 'core/audio/audio_engine_provider.dart';
import 'core/audio/audio_media_session_port.dart';
import 'core/audio/audio_media_session_provider.dart';
import 'core/audio/just_audio_adapter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = JustAudioAdapter();
  runApp(
    ProviderScope(
      overrides: [
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

final class EnglishLearningWebApp extends StatelessWidget {
  const EnglishLearningWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'English Learning Player',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const WebLibraryPage(),
  );
}
