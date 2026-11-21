import 'audio_engine.dart';
import 'audio_media_session_port.dart';
import 'audio_media_session_factory_native.dart'
    if (dart.library.js_interop) 'audio_media_session_factory_web.dart'
    as impl;

Future<AudioMediaSessionPort> createAudioMediaSession(AudioEngine engine) =>
    impl.create(engine);
