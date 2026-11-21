import 'package:audio_service/audio_service.dart' as service;

import 'audio_engine.dart';
import 'audio_media_session_port.dart';
import 'english_audio_handler.dart';

const audioServiceConfig = service.AudioServiceConfig(
  androidNotificationChannelId: 'com.linli.englishlearningplayer.audio',
  androidNotificationChannelName: 'English Learning Player',
  androidNotificationOngoing: false,
  androidStopForegroundOnPause: false,
);

Future<AudioMediaSessionPort> create(AudioEngine engine) async {
  final handler = EnglishAudioHandler(engine);
  try {
    return await service.AudioService.init<EnglishAudioHandler>(
      builder: () => handler,
      config: audioServiceConfig,
    );
  } catch (_) {
    await handler.close();
    rethrow;
  }
}
