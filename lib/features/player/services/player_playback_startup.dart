import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/audio_media_session_port.dart';
import '../../progress/data/progress_repository.dart';
import 'material_playback_loader.dart';

/// Prepares an audio source and its resume position for a playback session.
final class PlayerPlaybackStartup {
  const PlayerPlaybackStartup(this._audio);

  final AudioEngine _audio;

  Future<ProgressRepository?> prepare(
    MaterialPlaybackBundle bundle, {
    required Future<AudioMediaSessionPort> Function() mediaSession,
    required Future<ProgressRepository> Function() progressRepository,
    required bool restorePosition,
    required bool Function() isCurrent,
  }) async {
    await _audio.load(bundle.source);
    if (!isCurrent()) return null;
    try {
      final media = await mediaSession();
      if (!isCurrent()) return null;
      await media.publishMediaItem(
        id: bundle.material.id,
        title: bundle.material.title,
        durationMs: _audio.snapshot.durationMs,
      );
    } catch (_) {
      // A platform media session failure cannot block foreground playback.
    }
    if (!isCurrent()) return null;
    final repository = await progressRepository();
    if (!isCurrent()) return null;
    if (restorePosition) {
      final saved = await repository.canonical(bundle.material.id);
      if (!isCurrent()) return null;
      final positionMs = saved?.checkpoint.positionMs ?? 0;
      if (positionMs > 0) {
        await _audio.seekTo(Duration(milliseconds: positionMs));
      }
    }
    return isCurrent() ? repository : null;
  }
}
