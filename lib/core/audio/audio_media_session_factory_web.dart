import 'audio_engine.dart';
import 'audio_media_session_port.dart';

Future<AudioMediaSessionPort> create(AudioEngine engine) async =>
    const NoopAudioMediaSession();
