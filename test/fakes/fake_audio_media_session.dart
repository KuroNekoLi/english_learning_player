import 'package:english_learning_player/core/audio/audio_media_session_port.dart';

final class FakeAudioMediaSession implements AudioMediaSessionPort {
  String? id;
  String? title;
  int? durationMs;

  @override
  Future<void> publishMediaItem({
    required String id,
    required String title,
    required int? durationMs,
  }) async {
    this.id = id;
    this.title = title;
    this.durationMs = durationMs;
  }
}
