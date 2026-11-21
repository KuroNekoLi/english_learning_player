final class MediaSource {
  const MediaSource({required this.materialId, required this.uri});

  final String materialId;

  /// App-managed file URI or an authorized short-lived remote URI.
  final Uri uri;
}

final class TimeRange {
  TimeRange(this.startMs, this.endMs) {
    if (startMs < 0 || endMs <= startMs) {
      throw ArgumentError('Expected a non-empty half-open millisecond range.');
    }
  }

  final int startMs;
  final int endMs;
}

enum AudioProcessingState { idle, loading, buffering, ready, completed, error }

final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.processingState,
    this.materialId,
    this.positionMs = 0,
    this.durationMs,
    this.bufferedMs,
    this.playing = false,
    this.speed = 1,
    this.currentLoop,
    this.error,
  });

  final String? materialId;
  final int positionMs;
  final int? durationMs;
  final int? bufferedMs;
  final bool playing;
  final AudioProcessingState processingState;
  final double speed;
  final TimeRange? currentLoop;
  final AudioEngineException? error;
}

enum AudioFailure {
  sourceUnavailable,
  unsupportedFormat,
  interrupted,
  superseded,
  platform,
}

final class AudioEngineException implements Exception {
  const AudioEngineException(this.failure);

  final AudioFailure failure;
}

/// The owner disposes the engine. Latest load and seek win over earlier work.
abstract interface class AudioEngine {
  PlaybackSnapshot get snapshot;
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> load(MediaSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  /// Stop and discard the current source so it cannot be resumed.
  Future<void> unload();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setSentenceLoop(TimeRange? range);
  Future<void> dispose();
}
