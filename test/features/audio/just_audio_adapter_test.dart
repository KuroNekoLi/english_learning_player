import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/audio_player_port.dart';
import 'package:english_learning_player/core/audio/just_audio_adapter.dart';
import '../../fakes/fake_audio_player_port.dart';

void main() {
  group('JustAudioAdapter', () {
    late FakeAudioPlayerPort player;
    late JustAudioAdapter engine;

    setUp(() {
      player = FakeAudioPlayerPort();
      engine = JustAudioAdapter(player: player);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('T-AUDIO-01 loads media and reports source failures', () async {
      await engine.load(_source('lesson-a'));
      expect(engine.snapshot.materialId, 'lesson-a');
      expect(engine.snapshot.durationMs, 10000);
      expect(engine.snapshot.processingState, AudioProcessingState.ready);

      player.nextError = StateError('missing media');
      await expectLater(
        engine.load(_source('missing')),
        throwsA(
          isA<AudioEngineException>().having(
            (error) => error.failure,
            'failure',
            AudioFailure.sourceUnavailable,
          ),
        ),
      );
      expect(engine.snapshot.processingState, AudioProcessingState.error);
      expect(engine.snapshot.materialId, 'missing');
    });

    test('T-AUDIO-02 clamps seeks and the last queued seek wins', () async {
      await engine.load(_source('lesson-a'));
      await engine.seekTo(const Duration(milliseconds: -5));
      expect(engine.snapshot.positionMs, 0);
      await engine.seekTo(const Duration(seconds: 20));
      expect(engine.snapshot.positionMs, 10000);

      final first = engine.seekTo(const Duration(seconds: 2));
      final last = engine.seekTo(const Duration(seconds: 7));
      await Future.wait([first, last]);
      expect(engine.snapshot.positionMs, 7000);
      expect(player.position.inMilliseconds, 7000);
    });

    test(
      'T-AUDIO-03 accepts supported speed and rejects other values',
      () async {
        await engine.load(_source('lesson-a'));
        await engine.setSpeed(0.5);
        expect(engine.snapshot.speed, 0.5);
        await engine.setSpeed(2);
        expect(engine.snapshot.speed, 2);
        expect(() => engine.setSpeed(2.01), throwsArgumentError);
        expect(() => engine.setSpeed(double.nan), throwsArgumentError);
      },
    );

    test(
      'T-AUDIO-04 pause and stop are repeatable and reset position',
      () async {
        await engine.load(_source('lesson-a'));
        await engine.play();
        await engine.pause();
        await engine.pause();
        expect(engine.snapshot.playing, isFalse);
        await engine.seekTo(const Duration(seconds: 4));
        await engine.stop();
        await engine.stop();
        expect(engine.snapshot.playing, isFalse);
        expect(engine.snapshot.positionMs, 0);
      },
    );

    test(
      'T-AUDIO-05 configures a clipped loop and clears it on outside seek',
      () async {
        await engine.load(_source('lesson-a'));
        await engine.seekTo(const Duration(seconds: 3));
        await engine.play();
        final loop = TimeRange(1000, 2500);
        await engine.setSentenceLoop(loop);
        expect(engine.snapshot.currentLoop, same(loop));
        expect(player.clip, same(loop));
        expect(player.loopEnabled, isTrue);
        expect(engine.snapshot.positionMs, 1000);
        expect(engine.snapshot.playing, isTrue);

        await engine.seekTo(const Duration(seconds: 5));
        expect(engine.snapshot.currentLoop, isNull);
        expect(player.clip, isNull);
        expect(player.loopEnabled, isFalse);
        expect(engine.snapshot.positionMs, 5000);
        expect(engine.snapshot.playing, isTrue);

        await engine.setSentenceLoop(TimeRange(6000, 8000));
        await engine.setSentenceLoop(null);
        expect(engine.snapshot.currentLoop, isNull);
        expect(player.clip, isNull);
        expect(player.loopEnabled, isFalse);

        await engine.setSentenceLoop(TimeRange(1000, 2000));
        await engine.load(_source('lesson-b'));
        expect(engine.snapshot.materialId, 'lesson-b');
        expect(engine.snapshot.currentLoop, isNull);
        expect(player.clip, isNull);
        expect(player.loopEnabled, isFalse);
      },
    );

    test(
      'T-AUDIO-06 latest source wins when an earlier load is pending',
      () async {
        final firstLoad = Completer<Duration?>();
        player.loadHandler = (uri) => uri.path.endsWith('first')
            ? firstLoad.future
            : Future.value(const Duration(seconds: 4));

        final first = engine.load(_source('first'));
        final second = engine.load(_source('second'));
        firstLoad.complete(const Duration(seconds: 8));
        await expectLater(
          first,
          throwsA(
            isA<AudioEngineException>().having(
              (error) => error.failure,
              'failure',
              AudioFailure.superseded,
            ),
          ),
        );
        await second;
        expect(engine.snapshot.materialId, 'second');
        expect(engine.snapshot.durationMs, 4000);
        expect(player.loadedUri, _source('second').uri);
      },
    );

    test(
      'T-AUDIO-07 snapshots stream current and changed playback state',
      () async {
        final snapshots = <PlaybackSnapshot>[];
        final subscription = engine.snapshots.listen(snapshots.add);
        await engine.load(_source('lesson-a'));
        player.bufferTo(2500);
        player.advanceTo(1200);

        expect(snapshots.first.processingState, AudioProcessingState.idle);
        expect(engine.snapshot.positionMs, 1200);
        expect(engine.snapshot.bufferedMs, 2500);
        expect(
          snapshots.any(
            (value) => value.processingState == AudioProcessingState.loading,
          ),
          isTrue,
        );
        await subscription.cancel();
      },
    );

    test('T-AUDIO-08 interruptions pause without automatic resume', () async {
      await engine.load(_source('lesson-a'));
      await engine.play();
      player.emitInterruption(AudioPortInterruption.began);
      await Future<void>.delayed(Duration.zero);
      expect(engine.snapshot.playing, isFalse);
      expect(engine.snapshot.error?.failure, AudioFailure.interrupted);

      player.emitInterruption(AudioPortInterruption.ended);
      await Future<void>.delayed(Duration.zero);
      expect(engine.snapshot.playing, isFalse);
      expect(player.playCalls, 1);
    });

    test('disposal releases the backend and rejects later commands', () async {
      await engine.dispose();
      expect(player.disposeCalls, 1);
      expect(() => engine.play(), throwsStateError);
    });
  });
}

MediaSource _source(String id) =>
    MediaSource(materialId: id, uri: Uri.parse('file:///tmp/$id.m4a'));
