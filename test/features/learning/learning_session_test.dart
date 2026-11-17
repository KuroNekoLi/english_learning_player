import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/features/learning/domain/learning_session.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import '../../fakes/fake_audio_engine.dart';

void main() {
  group('LearningSession', () {
    late FakeAudioEngine audio;
    late LearningSession session;

    setUp(() async {
      audio = FakeAudioEngine({_audioUri: 5000});
      await audio.load(MediaSource(materialId: 'lesson-1', uri: _audioUri));
      session = LearningSession(
        audioEngine: audio,
        englishTrack: _englishTrack,
        chineseTrack: _chineseTrack,
      );
    });

    tearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    test('T-LEARN-01 enforces blind then English then bilingual reveal', () {
      session.enterIntensive();
      expect(session.state.mode, LearningMode.intensive);
      expect(session.state.phase, IntensivePhase.blindListening);
      expect(session.state.subtitleVisibility, SubtitleVisibility.hidden);

      session.revealChinese();
      expect(session.state.phase, IntensivePhase.blindListening);
      session.revealEnglish();
      expect(session.state.phase, IntensivePhase.englishShown);
      expect(session.state.subtitleVisibility, SubtitleVisibility.englishOnly);
      session.revealChinese();
      expect(session.state.phase, IntensivePhase.bilingualShown);
      expect(session.state.subtitleVisibility, SubtitleVisibility.bilingual);
    });

    test('T-LEARN-02 missing translation reveals an explicit placeholder', () {
      final withoutChinese = LearningSession(
        audioEngine: audio,
        englishTrack: _englishTrack,
      );
      addTearDown(withoutChinese.dispose);
      withoutChinese.enterIntensive();
      withoutChinese.revealEnglish();
      withoutChinese.revealChinese();
      expect(
        withoutChinese.state.subtitleVisibility,
        SubtitleVisibility.bilingual,
      );
      expect(withoutChinese.state.translationCues, isEmpty);
      expect(withoutChinese.state.translationPlaceholder, '未提供翻譯');
    });

    test(
      'T-LEARN-03 next cue clears loop and resets the reveal mask',
      () async {
        await audio.seekTo(const Duration(milliseconds: 300));
        await _flushPlaybackEvents();
        session.enterIntensive();
        session.revealEnglish();
        session.revealChinese();
        await session.setCueLoopEnabled(true);
        expect(audio.snapshot.currentLoop, isNotNull);

        expect(await session.nextCue(), isTrue);
        await _flushPlaybackEvents();
        expect(audio.snapshot.positionMs, 1000);
        expect(audio.snapshot.currentLoop, isNull);
        expect(session.state.currentCue?.id, 'en-2');
        expect(session.state.phase, IntensivePhase.blindListening);
        expect(session.state.subtitleVisibility, SubtitleVisibility.hidden);
      },
    );

    test(
      'T-LEARN-04 cue loop can be toggled and replay preserves reveal state',
      () async {
        await audio.seekTo(const Duration(milliseconds: 300));
        await _flushPlaybackEvents();
        session.enterIntensive();
        session.revealEnglish();

        expect(await session.setCueLoopEnabled(true), isTrue);
        expect(audio.snapshot.currentLoop?.startMs, 0);
        expect(audio.snapshot.currentLoop?.endMs, 1000);
        expect(audio.snapshot.positionMs, 0);
        expect(audio.snapshot.playing, isTrue);

        audio.advanceTo(600);
        await _flushPlaybackEvents();
        expect(await session.replay(), isTrue);
        expect(audio.snapshot.positionMs, 0);
        expect(session.state.phase, IntensivePhase.englishShown);

        expect(await session.setCueLoopEnabled(false), isTrue);
        expect(audio.snapshot.currentLoop, isNull);
      },
    );

    test(
      'T-LEARN-05 follows playback snapshots and restores normal visibility',
      () async {
        final received = <LearningSessionState>[];
        final subscription = session.states.listen(received.add);
        await audio.seekTo(const Duration(milliseconds: 1300));
        await _flushPlaybackEvents();
        expect(session.state.currentCue?.id, 'en-2');
        expect(session.state.translationCues.single.id, 'zh-2');
        expect(received.any((state) => state.currentCue?.id == 'en-2'), isTrue);

        session.enterIntensive();
        session.revealEnglish();
        await session.exitIntensive();
        expect(session.state.mode, LearningMode.normal);
        expect(session.state.subtitleVisibility, SubtitleVisibility.bilingual);
        await subscription.cancel();
      },
    );

    test(
      'uses the English track offset for replay and loop time ranges',
      () async {
        final offsetSession = LearningSession(
          audioEngine: audio,
          englishTrack: _englishTrack.copyWith(offsetMs: 250),
        );
        addTearDown(offsetSession.dispose);
        await audio.seekTo(const Duration(milliseconds: 400));
        await _flushPlaybackEvents();
        expect(offsetSession.state.currentCue?.id, 'en-1');
        expect(await offsetSession.setCueLoopEnabled(true), isTrue);
        expect(audio.snapshot.currentLoop?.startMs, 250);
        expect(audio.snapshot.currentLoop?.endMs, 1250);
      },
    );

    test(
      'tapping another cue clears its loop and returns to blind listening',
      () async {
        await audio.seekTo(const Duration(milliseconds: 300));
        await _flushPlaybackEvents();
        session.enterIntensive();
        session.revealEnglish();
        await session.setCueLoopEnabled(true);

        expect(await session.playCue('en-2'), isTrue);
        expect(audio.snapshot.currentLoop, isNull);
        expect(audio.snapshot.positionMs, 1000);
        expect(session.state.currentCue?.id, 'en-2');
        expect(session.state.phase, IntensivePhase.blindListening);
      },
    );

    test(
      'selecting the already-looping cue switches to one-pass playback',
      () async {
        await audio.seekTo(const Duration(milliseconds: 300));
        await _flushPlaybackEvents();
        expect(await session.setCueLoopEnabled(true), isTrue);
        expect(audio.snapshot.currentLoop, isNotNull);

        expect(await session.playCue('en-1'), isTrue);
        expect(audio.snapshot.currentLoop, isNull);
        expect(audio.snapshot.positionMs, 0);
        expect(audio.snapshot.playing, isTrue);

        audio.advanceTo(1200);
        await _flushPlaybackEvents();
        expect(audio.snapshot.playing, isTrue);
        expect(session.state.currentCue?.id, 'en-2');
      },
    );

    test(
      'does not control audio after it switches to another material',
      () async {
        await audio.load(
          MediaSource(materialId: 'different-lesson', uri: _audioUri),
        );
        await _flushPlaybackEvents();
        expect(session.state.currentCue, isNull);
        expect(await session.replay(), isFalse);
        expect(await session.nextCue(), isFalse);
        expect(await session.setCueLoopEnabled(true), isFalse);
      },
    );

    test(
      'does not report a missing translation while playback is in a gap',
      () async {
        final withoutChinese = LearningSession(
          audioEngine: audio,
          englishTrack: _englishTrack,
        );
        addTearDown(withoutChinese.dispose);
        await audio.seekTo(const Duration(milliseconds: 3000));
        await _flushPlaybackEvents();
        expect(withoutChinese.state.currentCue, isNull);
        expect(withoutChinese.state.translationPlaceholder, isNull);
      },
    );
  });
}

Future<void> _flushPlaybackEvents() => Future<void>.delayed(Duration.zero);

final _audioUri = Uri.parse('file:///training.m4a');

final _englishTrack = SubtitleTrack(
  id: 'track-en',
  ownerId: 'owner-1',
  materialId: 'lesson-1',
  languageTag: 'en',
  sourceName: 'lesson.en.srt',
  originalBytes: const [],
  revision: 1,
  offsetMs: 0,
  selectionMode: SubtitleSelectionMode.automatic,
  isSelected: true,
  cues: const [
    SubtitleCue(
      id: 'en-1',
      sequence: 1,
      startMs: 0,
      endMs: 1000,
      text: 'First sentence.',
    ),
    SubtitleCue(
      id: 'en-2',
      sequence: 2,
      startMs: 1000,
      endMs: 2000,
      text: 'Second sentence.',
    ),
  ],
);

final _chineseTrack = SubtitleTrack(
  id: 'track-zh',
  ownerId: 'owner-1',
  materialId: 'lesson-1',
  languageTag: 'zh-TW',
  sourceName: 'lesson.zh-TW.srt',
  originalBytes: const [],
  revision: 1,
  offsetMs: 0,
  selectionMode: SubtitleSelectionMode.automatic,
  isSelected: true,
  cues: const [
    SubtitleCue(id: 'zh-1', sequence: 2, startMs: 0, endMs: 1000, text: '第一句。'),
    SubtitleCue(
      id: 'zh-2',
      sequence: 7,
      startMs: 1000,
      endMs: 2000,
      text: '第二句。',
    ),
  ],
);
