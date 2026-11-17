import '../../../core/sync/progress_policy.dart';
import '../data/progress_repository.dart';

/// Converts playback events into durable local checkpoints. Remote sync is
/// deliberately outside this recorder so remote data can never seek a player.
final class PlaybackProgressRecorder {
  PlaybackProgressRecorder({
    required ProgressRepository repository,
    required ProgressStream stream,
    required DateTime Function() clock,
    this.interval = const Duration(seconds: 15),
  }) : _repository = repository,
       _stream = stream,
       _clock = clock;

  final ProgressRepository _repository;
  final ProgressStream _stream;
  final DateTime Function() _clock;
  final Duration interval;
  DateTime? _lastCheckpointAt;
  int? _lastPositionMs;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  Future<void> onPlaybackSnapshot({
    required int positionMs,
    required bool playing,
  }) async {
    _ensureActive();
    final now = _clock().toUtc();
    final shouldWrite =
        _lastCheckpointAt == null ||
        now.difference(_lastCheckpointAt!) >= interval;
    if (shouldWrite) {
      await _write(
        positionMs,
        playing ? CheckpointState.playing : CheckpointState.paused,
        now,
      );
    }
    _lastPositionMs = positionMs;
  }

  Future<void> onPauseCompleted() => _writeLatest(CheckpointState.paused);
  Future<void> onSeekCompleted(int positionMs, {required bool playing}) =>
      _write(
        positionMs,
        playing ? CheckpointState.playing : CheckpointState.paused,
        _clock().toUtc(),
      );
  Future<void> onMaterialChanged() => _writeLatest(CheckpointState.stopped);
  Future<void> onLifecycleExit({int? positionMs}) async {
    _ensureActive();
    final position = positionMs ?? _lastPositionMs;
    if (position == null) return;
    await _write(position, CheckpointState.paused, _clock().toUtc());
  }

  Future<void> dispose({
    CheckpointState finalState = CheckpointState.paused,
  }) async {
    if (_disposed) return;
    final position = _lastPositionMs;
    if (position != null) await _write(position, finalState, _clock().toUtc());
    _disposed = true;
  }

  Future<void> _writeLatest(CheckpointState state) async {
    _ensureActive();
    final position = _lastPositionMs;
    if (position == null) return;
    await _write(position, state, _clock().toUtc());
  }

  Future<void> _write(
    int positionMs,
    CheckpointState state,
    DateTime now,
  ) async {
    _ensureActive();
    final previousCheckpointAt = _lastCheckpointAt;
    _lastPositionMs = positionMs;
    _lastCheckpointAt = now;
    final write = _writes.then((_) async {
      _ensureActive();
      await _repository.recordCheckpoint(
        stream: _stream,
        positionMs: positionMs,
        state: state,
        nowMs: now.millisecondsSinceEpoch,
      );
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    try {
      await write;
    } catch (_) {
      if (_lastCheckpointAt == now) _lastCheckpointAt = previousCheckpointAt;
      rethrow;
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Progress recorder has been disposed.');
  }
}
