abstract interface class AudioMediaSessionPort {
  Future<void> publishMediaItem({
    required String id,
    required String title,
    required int? durationMs,
  });
}

final class NoopAudioMediaSession implements AudioMediaSessionPort {
  const NoopAudioMediaSession();

  @override
  Future<void> publishMediaItem({
    required String id,
    required String title,
    required int? durationMs,
  }) async {}
}
