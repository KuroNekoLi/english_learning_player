import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine.dart';
import 'just_audio_adapter.dart';

/// Application playback dependency. Features should depend on AudioEngine,
/// never on just_audio or its platform implementation.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioAdapter();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});
