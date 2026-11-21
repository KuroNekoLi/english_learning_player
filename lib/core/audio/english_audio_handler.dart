import 'dart:async';

import 'package:audio_service/audio_service.dart' as service;

import 'audio_engine.dart';
import 'audio_media_session_port.dart';

/// Routes operating-system media controls back through the single AudioEngine.
final class EnglishAudioHandler extends service.BaseAudioHandler
    with service.SeekHandler
    implements AudioMediaSessionPort {
  EnglishAudioHandler(this._audioEngine) {
    _snapshotSubscription = _audioEngine.snapshots.listen(_publishSnapshot);
    _publishSnapshot(_audioEngine.snapshot);
  }

  final AudioEngine _audioEngine;
  late final StreamSubscription<PlaybackSnapshot> _snapshotSubscription;

  @override
  Future<void> publishMediaItem({
    required String id,
    required String title,
    required int? durationMs,
  }) async {
    if (_audioEngine.snapshot.materialId != id) return;
    mediaItem.add(
      service.MediaItem(
        id: id,
        title: title,
        album: 'English Learning Player',
        duration: durationMs == null
            ? null
            : Duration(milliseconds: durationMs),
      ),
    );
    _publishSnapshot(_audioEngine.snapshot);
  }

  @override
  Future<void> play() async {
    await _audioEngine.play();
    _publishSnapshot(_audioEngine.snapshot);
  }

  @override
  Future<void> pause() async {
    await _audioEngine.pause();
    _publishSnapshot(_audioEngine.snapshot);
  }

  @override
  Future<void> stop() async {
    await _audioEngine.stop();
    _publishSnapshot(_audioEngine.snapshot);
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioEngine.seekTo(position);
    _publishSnapshot(_audioEngine.snapshot);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _audioEngine.setSpeed(speed);
    _publishSnapshot(_audioEngine.snapshot);
  }

  Future<void> close() => _snapshotSubscription.cancel();

  void _publishSnapshot(PlaybackSnapshot snapshot) {
    if (snapshot.materialId == null && mediaItem.value != null) {
      mediaItem.add(null);
    }
    final controls = snapshot.materialId == null
        ? const <service.MediaControl>[]
        : snapshot.playing
        ? const [service.MediaControl.pause, service.MediaControl.stop]
        : const [service.MediaControl.play, service.MediaControl.stop];
    playbackState.add(
      service.PlaybackState(
        controls: controls,
        androidCompactActionIndices: controls.isEmpty ? const [] : const [0, 1],
        systemActions: const {
          service.MediaAction.seek,
          service.MediaAction.seekForward,
          service.MediaAction.seekBackward,
          service.MediaAction.setSpeed,
        },
        processingState: switch (snapshot.processingState) {
          AudioProcessingState.idle => service.AudioProcessingState.idle,
          AudioProcessingState.loading => service.AudioProcessingState.loading,
          AudioProcessingState.buffering =>
            service.AudioProcessingState.buffering,
          AudioProcessingState.ready => service.AudioProcessingState.ready,
          AudioProcessingState.completed =>
            service.AudioProcessingState.completed,
          AudioProcessingState.error => service.AudioProcessingState.error,
        },
        playing: snapshot.playing,
        updatePosition: Duration(milliseconds: snapshot.positionMs),
        bufferedPosition: snapshot.bufferedMs == null
            ? Duration.zero
            : Duration(milliseconds: snapshot.bufferedMs!),
        speed: snapshot.speed,
      ),
    );
  }
}
