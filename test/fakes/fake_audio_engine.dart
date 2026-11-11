import 'dart:async';

import 'package:english_learning_player/core/audio/audio_engine.dart';

final class FakeAudioEngine implements AudioEngine {
  FakeAudioEngine(this.durationsMs);

  final Map<Uri, int> durationsMs;
  final _events = StreamController<PlaybackSnapshot>.broadcast();
  MediaSource? _source;
  int? _durationMs;
  int _positionMs = 0;
  int? _bufferedMs;
  bool _playing = false;
  double _speed = 1;
  TimeRange? _loop;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  AudioEngineException? _error;

  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    materialId: _source?.materialId,
    positionMs: _positionMs,
    durationMs: _durationMs,
    bufferedMs: _bufferedMs,
    playing: _playing,
    speed: _speed,
    currentLoop: _loop,
    processingState: _processingState,
    error: _error,
  );

  @override
  Stream<PlaybackSnapshot> get snapshots => _events.stream;

  @override
  Future<void> load(MediaSource source) async {
    final durationMs = durationsMs[source.uri];
    if (durationMs == null) {
      _processingState = AudioProcessingState.error;
      _error = const AudioEngineException(AudioFailure.sourceUnavailable);
      _events.add(snapshot);
      throw const AudioEngineException(AudioFailure.sourceUnavailable);
    }
    _source = source;
    _durationMs = durationMs;
    _positionMs = 0;
    _playing = false;
    _loop = null;
    _bufferedMs = 0;
    _error = null;
    _processingState = AudioProcessingState.ready;
    _events.add(snapshot);
  }

  @override
  Future<void> play() async {
    _requireSource();
    _playing = true;
    _events.add(snapshot);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _events.add(snapshot);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _positionMs = 0;
    _loop = null;
    _processingState = _source == null
        ? AudioProcessingState.idle
        : AudioProcessingState.ready;
    _events.add(snapshot);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _requireSource();
    _positionMs = position.inMilliseconds.clamp(0, _durationMs!);
    _events.add(snapshot);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!speed.isFinite || speed < 0.5 || speed > 2) {
      throw ArgumentError.value(speed, 'speed');
    }
    _speed = speed;
    _events.add(snapshot);
  }

  @override
  Future<void> setSentenceLoop(TimeRange? range) async {
    if (range != null) {
      _requireSource();
      if (range.endMs > _durationMs!) throw ArgumentError.value(range, 'range');
    }
    _loop = range;
    _events.add(snapshot);
  }

  @override
  Future<void> dispose() => _events.close();

  /// Move the fake playhead explicitly; no wall-clock timer is involved.
  void advanceTo(int positionMs) {
    if (_source == null) return;
    final loop = _loop;
    if (loop != null && positionMs >= loop.endMs) {
      final loopLength = loop.endMs - loop.startMs;
      _positionMs = loop.startMs + (positionMs - loop.startMs) % loopLength;
    } else {
      _positionMs = positionMs.clamp(0, _durationMs!);
      if (_positionMs == _durationMs) {
        _playing = false;
        _processingState = AudioProcessingState.completed;
      }
    }
    _events.add(snapshot);
  }

  void setBufferedPosition(int positionMs) {
    _bufferedMs = positionMs.clamp(0, _durationMs ?? positionMs);
    _events.add(snapshot);
  }

  void fail(AudioFailure failure) {
    _playing = false;
    _processingState = AudioProcessingState.error;
    _error = AudioEngineException(failure);
    _events.add(snapshot);
  }

  /// Simulate an interruption. An ended event intentionally never resumes.
  void interruption({required bool began}) {
    if (began && _playing) {
      _playing = false;
      _processingState = AudioProcessingState.ready;
      _error = const AudioEngineException(AudioFailure.interrupted);
      _events.add(snapshot);
    }
  }

  void _requireSource() {
    if (_source == null) {
      throw const AudioEngineException(AudioFailure.sourceUnavailable);
    }
  }
}
