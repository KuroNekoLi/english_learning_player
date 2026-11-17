import 'dart:async';

import 'package:audio_service/audio_service.dart' as service;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine_provider.dart';
import 'audio_media_session_port.dart';
import 'english_audio_handler.dart';

const audioServiceConfig = service.AudioServiceConfig(
  androidNotificationChannelId: 'com.example.english_learning_player.audio',
  androidNotificationChannelName: 'English Learning Player',
  androidNotificationOngoing: false,
  androidStopForegroundOnPause: false,
);

final audioMediaSessionProvider = FutureProvider<AudioMediaSessionPort>((
  ref,
) async {
  final handler = EnglishAudioHandler(ref.watch(audioEngineProvider));
  ref.onDispose(() => unawaited(handler.close()));
  return service.AudioService.init<EnglishAudioHandler>(
    builder: () => handler,
    config: audioServiceConfig,
  );
});
