import 'dart:async';

import 'package:audio_service/audio_service.dart' as service;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_engine_provider.dart';
import 'core/audio/audio_media_session_port.dart';
import 'core/audio/audio_media_session_provider.dart';
import 'core/audio/english_audio_handler.dart';
import 'core/audio/just_audio_adapter.dart';
import 'app/library_page.dart';

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
  runApp(
    ProviderScope(
      overrides: [
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
      child: const EnglishLearningPlayer(),
    ),
  );
}

class EnglishLearningPlayer extends StatelessWidget {
  const EnglishLearningPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Learning Player',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const LibraryPage(),
    );
  }
}
