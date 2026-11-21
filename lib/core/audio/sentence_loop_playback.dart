import 'audio_engine.dart';
import 'audio_player_port.dart';

/// Applies and removes native clips. The AudioEngine serializes these calls
/// with other commands and owns the resulting playback snapshot.
final class SentenceLoopPlayback {
  const SentenceLoopPlayback(this._player);

  final AudioPlayerPort _player;

  Future<void> apply(TimeRange range) async {
    await _player.pause();
    await _player.setLoopEnabled(false);
    await _player.setClip(range);
    await _player.seekTo(range.startMs);
    await _player.setLoopEnabled(true);
  }

  Future<void> clearClip() async {
    await _player.setLoopEnabled(false);
    await _player.setClip(null);
  }

  Future<void> restorePosition(int positionMs) async {
    await clearClip();
    await _player.seekTo(positionMs);
  }
}
