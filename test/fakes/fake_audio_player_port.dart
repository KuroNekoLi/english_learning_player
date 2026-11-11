import 'dart:async';

import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/audio_player_port.dart';

final class FakeAudioPlayerPort implements AudioPlayerPort {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration?>.broadcast(sync: true);
  final _buffered = StreamController<Duration>.broadcast(sync: true);
  final _playingEvents = StreamController<bool>.broadcast(sync: true);
  final _speeds = StreamController<double>.broadcast(sync: true);
  final _states = StreamController<AudioPortProcessingState>.broadcast(
    sync: true,
  );
  final _errors = StreamController<Object>.broadcast(sync: true);
  final _interruptions = StreamController<AudioPortInterruption>.broadcast(
    sync: true,
  );

  Future<Duration?> Function(Uri uri)? loadHandler;
  Object? nextError;
  Uri? loadedUri;
  TimeRange? clip;
  bool loopEnabled = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Duration _position = Duration.zero;
  Duration? _duration;
  Duration _bufferedPosition = Duration.zero;
  bool _playing = false;
  double _speed = 1;
  AudioPortProcessingState _state = AudioPortProcessingState.idle;

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration?> get durationStream => _durations.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _buffered.stream;
  @override
  Stream<bool> get playingStream => _playingEvents.stream;
  @override
  Stream<double> get speedStream => _speeds.stream;
  @override
  Stream<AudioPortProcessingState> get processingStateStream => _states.stream;
  @override
  Stream<Object> get errors => _errors.stream;
  @override
  Stream<AudioPortInterruption> get interruptions => _interruptions.stream;

  @override
  Duration get position => _position;
  @override
  Duration? get duration => _duration;
  @override
  Duration get bufferedPosition => _bufferedPosition;
  @override
  bool get playing => _playing;
  @override
  double get speed => _speed;
  @override
  AudioPortProcessingState get processingState => _state;

  @override
  Future<Duration?> load(Uri uri) async {
    _setState(AudioPortProcessingState.loading);
    final handler = loadHandler;
    final result = handler == null
        ? const Duration(seconds: 10)
        : await handler(uri);
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    loadedUri = uri;
    _position = Duration.zero;
    _duration = result;
    _bufferedPosition = Duration.zero;
    _emitPosition();
    _durations.add(result);
    _buffered.add(_bufferedPosition);
    _setPlaying(false);
    _setState(AudioPortProcessingState.ready);
    return result;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _setPlaying(false);
  }

  @override
  Future<void> seekTo(int positionMs) async {
    _position = Duration(milliseconds: positionMs);
    _emitPosition();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    _speeds.add(speed);
  }

  @override
  Future<void> setClip(TimeRange? range) async {
    clip = range;
  }

  @override
  Future<void> setLoopEnabled(bool enabled) async {
    loopEnabled = enabled;
  }

  void advanceTo(int positionMs) {
    _position = Duration(milliseconds: positionMs);
    _emitPosition();
  }

  void bufferTo(int positionMs) {
    _bufferedPosition = Duration(milliseconds: positionMs);
    _buffered.add(_bufferedPosition);
  }

  void emitInterruption(AudioPortInterruption event) =>
      _interruptions.add(event);

  void emitError(Object error) => _errors.add(error);

  void _emitPosition() => _positions.add(_position);
  void _setPlaying(bool value) {
    _playing = value;
    _playingEvents.add(value);
  }

  void _setState(AudioPortProcessingState value) {
    _state = value;
    _states.add(value);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await Future.wait([
      _positions.close(),
      _durations.close(),
      _buffered.close(),
      _playingEvents.close(),
      _speeds.close(),
      _states.close(),
      _errors.close(),
      _interruptions.close(),
    ]);
  }
}
