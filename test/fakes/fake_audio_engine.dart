import 'dart:async';

import 'package:english_learning_player/core/audio/audio_engine.dart';

final class FakeAudioEngine implements AudioEngine {
  FakeAudioEngine(this.durationsMs);

  final Map<Uri, int> durationsMs;
  final _events = StreamController<PlaybackSnapshot>.broadcast();
  MediaSource? _source;
  int? _durationMs;
  int _positionMs = 0;
  bool _playing = false;
  double _speed = 1;
  TimeRange? _loop;

  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    materialId: _source?.materialId,
    positionMs: _positionMs,
    durationMs: _durationMs,
    playing: _playing,
    speed: _speed,
    currentLoop: _loop,
    processingState: _source == null
        ? AudioProcessingState.idle
        : AudioProcessingState.ready,
  );

  @override
  Stream<PlaybackSnapshot> get snapshots => _events.stream;

  @override
  Future<void> load(MediaSource source) async {
    final durationMs = durationsMs[source.uri];
    if (durationMs == null) {
      throw const AudioEngineException(AudioFailure.sourceUnavailable);
    }
    _source = source;
    _durationMs = durationMs;
    _positionMs = 0;
    _playing = false;
    _loop = null;
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

  void _requireSource() {
    if (_source == null) {
      throw const AudioEngineException(AudioFailure.sourceUnavailable);
    }
  }
}
