import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_engine.dart';
import 'audio_engine_provider.dart';

abstract interface class SpeechPort {
  Future<void> speak(String text, String locale);
  Future<void> stop();
}

final speechPlaybackProvider = Provider<SpeechPlayback>(
  (ref) => SpeechPlayback(ref.watch(audioEngineProvider), _PlatformSpeech()),
);

/// Coordinates system synthesis with the existing media playback gateway.
final class SpeechPlayback {
  SpeechPlayback(this._audio, this._speech);

  final AudioEngine _audio;
  final SpeechPort _speech;
  Future<void> _pending = Future.value();
  Object? _owner;
  Object? _latestCommand;
  bool _started = false;

  Future<void> speak(Object owner, String text, String locale) {
    final command = Object();
    _owner = owner;
    _latestCommand = command;
    return _queue(() async {
      if (_latestCommand != command) return;
      if (_started) await _speech.stop();
      _started = false;
      if (_audio.snapshot.playing) await _audio.pause();
      if (_latestCommand != command) return;
      _started = true;
      await _speech.speak(text, locale);
    });
  }

  Future<void> stop(Object owner) {
    if (_owner != owner) return Future.value();
    _owner = null;
    _latestCommand = null;
    return _queue(() async {
      if (!_started) return;
      await _speech.stop();
      _started = false;
    });
  }

  Future<void> _queue(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class _PlatformSpeech implements SpeechPort {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> speak(String text, String locale) async {
    // The web plugin returns success from setLanguage even without a voice.
    if (kIsWeb && await _tts.isLanguageAvailable(locale) != true) {
      throw StateError('Speech language unavailable');
    }
    final language = await _tts.setLanguage(locale);
    if (language == null || language == 0 || language == false) {
      throw StateError('Speech language unavailable');
    }
    final started = await _tts.speak(text);
    if (started == 0 || started == false) {
      throw StateError('Speech playback unavailable');
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
