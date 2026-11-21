import 'dart:async';
import 'dart:io';

import 'audio_engine.dart';
import 'audio_player_port.dart';
import 'just_audio_player_port.dart';
import 'sentence_loop_playback.dart';

final class JustAudioAdapter implements AudioEngine {
  JustAudioAdapter({AudioPlayerPort? player})
    : _player = player ?? JustAudioPlayerPort() {
    _snapshot = _buildSnapshot();
    _subscriptions
      ..add(_player.positionStream.listen(_onPosition, onError: _onStreamError))
      ..add(_player.durationStream.listen(_onDuration, onError: _onStreamError))
      ..add(
        _player.bufferedPositionStream.listen(
          _onBufferedPosition,
          onError: _onStreamError,
        ),
      )
      ..add(_player.playingStream.listen(_onPlaying, onError: _onStreamError))
      ..add(_player.speedStream.listen(_onSpeed, onError: _onStreamError))
      ..add(
        _player.processingStateStream.listen(
          _onProcessingState,
          onError: _onStreamError,
        ),
      )
      ..add(_player.errors.listen(_onBackendError, onError: _onStreamError))
      ..add(_player.interruptions.listen(_onInterruption));
  }

  final AudioPlayerPort _player;
  late final _sentenceLoop = SentenceLoopPlayback(_player);
  final StreamController<PlaybackSnapshot> _events =
      StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _operationTail = Future<void>.value();

  late PlaybackSnapshot _snapshot;
  String? _materialId;
  int _positionMs = 0;
  int? _sourceDurationMs;
  int? _bufferedMs;
  bool _playing = false;
  double _speed = 1;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  TimeRange? _loopRange;
  AudioEngineException? _error;
  int _loadGeneration = 0;
  bool _loading = false;
  bool _configuringLoop = false;
  bool _disposed = false;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<PlaybackSnapshot> get snapshots => Stream.multi((controller) {
    controller.add(_snapshot);
    final subscription = _events.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<void> load(MediaSource source) {
    _ensureUsable();
    final generation = ++_loadGeneration;
    _loading = true;
    _materialId = source.materialId;
    _positionMs = 0;
    _sourceDurationMs = null;
    _bufferedMs = null;
    _playing = false;
    _processingState = AudioProcessingState.loading;
    _loopRange = null;
    _error = null;
    _publish();

    return _enqueue(() async {
      if (generation != _loadGeneration) _throwSuperseded();
      try {
        await _player.pause();
        await _sentenceLoop.clearClip();
        final duration = await _player.load(source.uri);
        if (generation != _loadGeneration) _throwSuperseded();
        _sourceDurationMs =
            _durationInMs(duration) ?? _durationInMs(_player.duration);
        _positionMs = _clampPosition(_durationInMs(_player.position) ?? 0);
        _bufferedMs = _durationInMs(_player.bufferedPosition);
        _playing = _player.playing;
        _processingState = _mapProcessingState(_player.processingState);
        if (_processingState == AudioProcessingState.idle ||
            _processingState == AudioProcessingState.loading) {
          _processingState = AudioProcessingState.ready;
        }
        _loading = false;
        _error = null;
        _publish();
      } catch (error) {
        if (generation != _loadGeneration) _throwSuperseded();
        _loading = false;
        _playing = false;
        _processingState = AudioProcessingState.error;
        _error = _mapFailure(error, loadingSource: true);
        _publish();
        throw _error!;
      }
    });
  }

  @override
  Future<void> play() {
    _ensureUsable();
    return _enqueue(() async {
      _requireSource();
      if (_processingState == AudioProcessingState.completed) {
        await _player.seekTo(_loopRange?.startMs ?? 0);
        _positionMs = _loopRange?.startMs ?? 0;
      }
      await _player.play();
      _playing = true;
      _error = null;
      if (_processingState == AudioProcessingState.completed ||
          _processingState == AudioProcessingState.idle) {
        _processingState = AudioProcessingState.ready;
      }
      _publish();
    });
  }

  @override
  Future<void> pause() {
    _ensureUsable();
    return _enqueue(() async {
      await _player.pause();
      _playing = false;
      _publish();
    });
  }

  @override
  Future<void> stop() {
    _ensureUsable();
    return _enqueue(() async {
      if (_loopRange != null) await _clearLoopInternal();
      await _player.stop();
      if (_materialId != null) await _player.seekTo(0);
      _playing = false;
      _positionMs = 0;
      _bufferedMs = _bufferedMs == null ? null : 0;
      _processingState = _materialId == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready;
      _publish();
    });
  }

  @override
  Future<void> unload() {
    _ensureUsable();
    final generation = ++_loadGeneration;
    _loading = true;
    _materialId = null;
    return _enqueue(() async {
      try {
        await _player.stop();
        await _player.clearSource();
      } finally {
        if (generation == _loadGeneration) {
          _loading = false;
          _positionMs = 0;
          _sourceDurationMs = null;
          _bufferedMs = null;
          _playing = false;
          _processingState = AudioProcessingState.idle;
          _loopRange = null;
          _error = null;
          _publish();
        }
      }
    });
  }

  @override
  Future<void> seekTo(Duration position) {
    _ensureUsable();
    return _enqueue(() async {
      _requireSource();
      final target = _clampPosition(position.inMilliseconds);
      final loop = _loopRange;
      if (loop != null && (target < loop.startMs || target >= loop.endMs)) {
        await _clearLoopInternal();
      }
      await _player.seekTo(target);
      _positionMs = target;
      _publish();
    });
  }

  @override
  Future<void> setSpeed(double speed) {
    _ensureUsable();
    if (!speed.isFinite || speed < 0.5 || speed > 2.0) {
      throw ArgumentError.value(
        speed,
        'speed',
        'Expected a value in [0.5, 2.0].',
      );
    }
    return _enqueue(() async {
      await _player.setSpeed(speed);
      _speed = speed;
      _publish();
    });
  }

  @override
  Future<void> setSentenceLoop(TimeRange? range) {
    _ensureUsable();
    return _enqueue(() async {
      if (range == null) {
        if (_loopRange != null) await _clearLoopInternal();
        return;
      }
      _requireSource();
      final duration = _sourceDurationMs;
      if (duration != null && range.endMs > duration) {
        throw ArgumentError.value(
          range,
          'range',
          'Range exceeds media duration.',
        );
      }
      if (_loopRange?.startMs == range.startMs &&
          _loopRange?.endMs == range.endMs) {
        return;
      }

      final previousPosition = _positionMs;
      final resumePlayback = _playing;
      _configuringLoop = true;
      try {
        await _sentenceLoop.apply(range);
        _loopRange = range;
        _positionMs = range.startMs;
        _playing = false;
        if (resumePlayback) {
          await _player.play();
          _playing = true;
        }
        _error = null;
        _publish();
      } catch (error) {
        await _restoreUnlooped(previousPosition, resumePlayback);
        throw _mapFailure(error);
      } finally {
        _configuringLoop = false;
      }
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _player.dispose();
    await _events.close();
  }

  Future<void> _clearLoopInternal() async {
    final previousPosition = _positionMs;
    final resumePlayback = _playing;
    _configuringLoop = true;
    try {
      await _player.pause();
      final restoredPosition = _clampPosition(previousPosition);
      await _sentenceLoop.restorePosition(restoredPosition);
      _loopRange = null;
      _positionMs = restoredPosition;
      _playing = false;
      if (resumePlayback) {
        await _player.play();
        _playing = true;
      }
      _publish();
    } catch (error) {
      _processingState = AudioProcessingState.error;
      _error = _mapFailure(error);
      _playing = false;
      _publish();
      rethrow;
    } finally {
      _configuringLoop = false;
    }
  }

  Future<void> _restoreUnlooped(int positionMs, bool resumePlayback) async {
    try {
      await _sentenceLoop.restorePosition(_clampPosition(positionMs));
      _loopRange = null;
      _positionMs = _clampPosition(positionMs);
      _playing = false;
      if (resumePlayback) {
        await _player.play();
        _playing = true;
      }
      _processingState = AudioProcessingState.ready;
      _publish();
    } catch (restoreError) {
      _processingState = AudioProcessingState.error;
      _error = _mapFailure(restoreError);
      _playing = false;
      _publish();
    }
  }

  void _onPosition(Duration value) {
    if (_materialId == null) return;
    if (_loading || _configuringLoop || _disposed) return;
    _positionMs = _clampPosition(value.inMilliseconds);
    _publish();
  }

  void _onDuration(Duration? value) {
    if (_materialId == null) return;
    if (_loading || _configuringLoop || _loopRange != null || _disposed) return;
    _sourceDurationMs = _durationInMs(value);
    _positionMs = _clampPosition(_positionMs);
    _publish();
  }

  void _onBufferedPosition(Duration value) {
    if (_materialId == null) return;
    if (_loading || _configuringLoop || _disposed) return;
    _bufferedMs = _clampPosition(value.inMilliseconds);
    _publish();
  }

  void _onPlaying(bool value) {
    if (_materialId == null) return;
    if (_loading || _configuringLoop || _disposed) return;
    _playing = value;
    _publish();
  }

  void _onSpeed(double value) {
    if (_disposed || !value.isFinite) return;
    _speed = value;
    _publish();
  }

  void _onProcessingState(AudioPortProcessingState value) {
    if (_materialId == null) return;
    if (_loading || _configuringLoop || _disposed) return;
    _processingState = _mapProcessingState(value);
    if (_processingState == AudioProcessingState.error) {
      _playing = false;
      _error ??= const AudioEngineException(AudioFailure.platform);
      unawaited(_player.pause());
    } else if (_processingState == AudioProcessingState.completed && _playing) {
      _playing = false;
      unawaited(_player.pause());
    }
    _publish();
  }

  void _onBackendError(Object error) {
    if (_materialId == null) return;
    if (_loading || _disposed) return;
    _processingState = AudioProcessingState.error;
    _playing = false;
    _error = _mapFailure(error);
    unawaited(_player.pause());
    _publish();
  }

  void _onStreamError(Object error, StackTrace stackTrace) =>
      _onBackendError(error);

  void _onInterruption(AudioPortInterruption interruption) {
    if (_materialId == null) return;
    if (_disposed) return;
    if (interruption == AudioPortInterruption.ended) return;
    if (interruption == AudioPortInterruption.began && !_playing) return;
    unawaited(
      _enqueue(() async {
        await _player.pause();
        _playing = false;
        _error = const AudioEngineException(AudioFailure.interrupted);
        _publish();
      }),
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final task = _operationTail.catchError((Object _) {}).then((_) async {
      _ensureUsable();
      await operation();
    });
    _operationTail = task.catchError((Object _) {});
    return task;
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('AudioEngine has been disposed.');
  }

  void _requireSource() {
    if (_materialId == null ||
        _processingState == AudioProcessingState.error &&
            _error?.failure != AudioFailure.interrupted) {
      throw const AudioEngineException(AudioFailure.sourceUnavailable);
    }
  }

  int _clampPosition(int value) {
    final lowerBounded = value < 0 ? 0 : value;
    final duration = _sourceDurationMs;
    if (duration == null) return lowerBounded;
    return lowerBounded > duration ? duration : lowerBounded;
  }

  int? _durationInMs(Duration? value) => value?.inMilliseconds;

  AudioProcessingState _mapProcessingState(AudioPortProcessingState state) =>
      switch (state) {
        AudioPortProcessingState.idle =>
          _materialId == null
              ? AudioProcessingState.idle
              : AudioProcessingState.ready,
        AudioPortProcessingState.loading => AudioProcessingState.loading,
        AudioPortProcessingState.buffering => AudioProcessingState.buffering,
        AudioPortProcessingState.ready => AudioProcessingState.ready,
        AudioPortProcessingState.completed => AudioProcessingState.completed,
      };

  AudioEngineException _mapFailure(Object error, {bool loadingSource = false}) {
    if (error is AudioEngineException) return error;
    if (error is FormatException) {
      return const AudioEngineException(AudioFailure.unsupportedFormat);
    }
    if (error is FileSystemException || loadingSource) {
      return const AudioEngineException(AudioFailure.sourceUnavailable);
    }
    return const AudioEngineException(AudioFailure.platform);
  }

  void _throwSuperseded() =>
      throw const AudioEngineException(AudioFailure.superseded);

  void _publish() {
    if (_disposed) return;
    _snapshot = _buildSnapshot();
    _events.add(_snapshot);
  }

  PlaybackSnapshot _buildSnapshot() => PlaybackSnapshot(
    materialId: _materialId,
    positionMs: _positionMs,
    durationMs: _sourceDurationMs,
    bufferedMs: _bufferedMs,
    playing: _playing,
    processingState: _processingState,
    speed: _speed,
    currentLoop: _loopRange,
    error: _error,
  );
}
