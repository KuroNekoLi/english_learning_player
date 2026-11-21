import 'audio_engine.dart';

enum AudioPortProcessingState { idle, loading, buffering, ready, completed }

enum AudioPortInterruption { began, ended, outputBecameNoisy }

/// Test seam for the native playback plugin.
abstract interface class AudioPlayerPort {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<bool> get playingStream;
  Stream<double> get speedStream;
  Stream<AudioPortProcessingState> get processingStateStream;
  Stream<Object> get errors;
  Stream<AudioPortInterruption> get interruptions;

  Duration get position;
  Duration? get duration;
  Duration get bufferedPosition;
  bool get playing;
  double get speed;
  AudioPortProcessingState get processingState;

  Future<Duration?> load(Uri uri);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> clearSource();
  Future<void> seekTo(int positionMs);
  Future<void> setSpeed(double speed);
  Future<void> setClip(TimeRange? range);
  Future<void> setLoopEnabled(bool enabled);
  Future<void> dispose();
}
