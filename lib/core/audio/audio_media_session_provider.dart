import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine_provider.dart';
import 'audio_media_session_port.dart';
import 'audio_media_session_factory.dart';

final audioMediaSessionProvider = FutureProvider<AudioMediaSessionPort>(
  (ref) async => createAudioMediaSession(ref.watch(audioEngineProvider)),
);
