import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/english_audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_audio_engine.dart';

void main() {
  late FakeAudioEngine engine;
  late EnglishAudioHandler handler;
  final source = Uri.parse('file:///lesson.m4a');

  setUp(() async {
    engine = FakeAudioEngine({source: 60000});
    await engine.load(MediaSource(materialId: 'lesson-1', uri: source));
    handler = EnglishAudioHandler(engine);
  });

  tearDown(() async {
    await handler.close();
    await engine.dispose();
  });

  test(
    'publishes media metadata and follows the AudioEngine snapshot',
    () async {
      await handler.publishMediaItem(
        id: 'lesson-1',
        title: 'A listening lesson',
        durationMs: 60000,
      );
      expect(handler.mediaItem.value?.id, 'lesson-1');
      expect(handler.mediaItem.value?.title, 'A listening lesson');
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 1));

      await handler.play();
      expect(engine.playCalls, 1);
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.controls, isNotEmpty);
    },
  );

  test('unload clears system media item and prevents resume', () async {
    await handler.publishMediaItem(
      id: 'lesson-1',
      title: 'Previous account lesson',
      durationMs: 60000,
    );
    await handler.play();
    await engine.unload();
    await Future<void>.delayed(Duration.zero);

    expect(engine.snapshot.materialId, isNull);
    expect(engine.snapshot.playing, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.controls, isEmpty);
    await expectLater(handler.play(), throwsA(isA<AudioEngineException>()));
  });

  test(
    'system pause, seek, stop and speed commands use AudioEngine only',
    () async {
      await handler.play();
      await handler.seek(const Duration(seconds: 20));
      expect(engine.seekCalls, 1);
      expect(engine.snapshot.positionMs, 20000);

      await handler.pause();
      expect(engine.snapshot.playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);

      await handler.setSpeed(1.25);
      expect(engine.snapshot.speed, 1.25);

      await handler.stop();
      expect(engine.snapshot.positionMs, 0);
      expect(handler.playbackState.value.processingState.name, 'ready');
    },
  );
}
