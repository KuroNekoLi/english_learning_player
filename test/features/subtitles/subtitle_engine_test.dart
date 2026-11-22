import 'dart:convert';

import 'package:english_learning_player/features/subtitles/domain/srt_parser.dart';
import 'package:english_learning_player/features/subtitles/domain/bilingual_subtitle_splitter.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_aligner.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_filename_matcher.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_language_detector.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_synchronizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SrtParser', () {
    const parser = SrtParser();

    test('parses BOM, CRLF, multiline text and non-contiguous sequences', () {
      final body =
          '1\r\n00:00:01,000 --> 00:00:02,250\r\nFirst line\r\nsecond line\r\n\r\n'
          '4\r\n00:00:03,000 --> 00:00:04,000\r\nNext\r\n\r\n'
          '9\r\n00:00:05,000 --> 00:00:06,000\r\nLast';
      final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode(body)];

      final document = parser.parse(bytes);

      expect(document.originalBytes, bytes);
      expect(document.cues.map((cue) => cue.sequence), [1, 4, 9]);
      expect(document.cues.first.startMs, 1000);
      expect(document.cues.first.endMs, 2250);
      expect(document.cues.first.text, 'First line\nsecond line');
      expect(document.warnings, isEmpty);
    });

    test(
      'reports malformed and invalid intervals without losing valid cues',
      () {
        final document = parser.parse(
          utf8.encode('''
1
00:00:02,000 --> 00:00:01,000
Backwards

bad index
not a timestamp
Broken

7
00:00:03,000 --> 00:00:04,000
Valid
'''),
        );

        expect(document.cues, hasLength(1));
        expect(document.cues.single.sequence, 7);
        expect(document.warnings.map((warning) => warning.code), [
          'invalidInterval',
          'missingSequence',
          'invalidTimestamp',
        ]);
      },
    );

    test('invalid UTF-8 returns a recoverable parse error', () {
      try {
        parser.parse([0xff, 0xfe, 0xff]);
        fail('Expected a recoverable encoding error.');
      } on SubtitleParseException catch (error) {
        expect(error.code, 'invalidUtf8');
        expect(error.recoverable, isTrue);
      }
    });

    test('handles a file without a trailing blank line', () {
      final document = parser.parse(
        utf8.encode('1\n00:00:00,000 --> 00:00:00,100\nReady'),
      );
      expect(document.cues.single.text, 'Ready');
    });

    test(
      'warns about invalid SRT sequence without coupling cue identity to it',
      () {
        final document = parser.parse(
          utf8.encode('0\n00:00:00,000 --> 00:00:00,100\nCue'),
        );
        expect(document.cues.single.sequence, 0);
        expect(document.cues.single.id, 'cue-0');
        expect(document.warnings.single.code, 'invalidSequence');
      },
    );
  });

  group('SubtitleFilenameMatcher', () {
    const matcher = SubtitleFilenameMatcher();

    test('matches supported language suffixes case-insensitively', () {
      final files = [
        'lesson.en.srt',
        'lesson.en-US.srt',
        'lesson.zh.srt',
        'lesson.zh-TW.srt',
        'lesson_English.srt',
        'lesson_Chinese.srt',
      ];
      final result = matcher.match(
        audioFileName: 'LESSON.M4A',
        subtitleFileNames: files,
      );

      expect(
        result[SubtitleLanguage.english]!.status,
        SubtitleMatchStatus.ambiguous,
      );
      expect(result[SubtitleLanguage.english]!.candidates, [
        'lesson.en-US.srt',
        'lesson.en.srt',
        'lesson_English.srt',
      ]);
      expect(
        result[SubtitleLanguage.chinese]!.status,
        SubtitleMatchStatus.ambiguous,
      );
    });

    test('normalizes Unicode and does not match similar stems', () {
      const composed = 'Caf\u00e9.mp3';
      const decomposedCandidate = 'Cafe\u0301.en.srt';
      final result = matcher.match(
        audioFileName: composed,
        subtitleFileNames: [
          decomposedCandidate,
          'Cafe_2.en.srt',
          'Café_extra.zh.srt',
        ],
      );
      expect(
        result[SubtitleLanguage.english]!.selectedSourceName,
        decomposedCandidate,
      );
      expect(
        result[SubtitleLanguage.chinese]!.status,
        SubtitleMatchStatus.missing,
      );
    });

    test(
      'matches an unlabelled SRT only when its full stem equals the audio',
      () {
        expect(
          matcher.matchUnlabelled(
            audioFileName: 'Lesson.M4A',
            subtitleFileNames: [
              'lesson.srt',
              'lesson.en.srt',
              'lesson_2.srt',
              'another-lesson.srt',
            ],
          ),
          ['lesson.srt'],
        );
      },
    );

    test('manual selection remains authoritative when candidates change', () {
      final result = matcher.match(
        audioFileName: 'lesson.mp3',
        subtitleFileNames: ['lesson.en.srt', 'lesson.en-US.srt'],
        manualSelections: const {SubtitleLanguage.english: 'custom-notes.srt'},
      );
      final english = result[SubtitleLanguage.english]!;
      expect(english.status, SubtitleMatchStatus.manual);
      expect(english.selectedSourceName, 'custom-notes.srt');
      expect(english.requiresUserChoice, isFalse);
    });

    test(
      'a subtitle arriving later can be matched without a prior candidate',
      () {
        final before = matcher.match(
          audioFileName: 'lesson.mp3',
          subtitleFileNames: ['lesson.en.srt'],
        );
        final after = matcher.match(
          audioFileName: 'lesson.mp3',
          subtitleFileNames: ['lesson.en.srt', 'lesson.zh-TW.srt'],
        );
        expect(
          before[SubtitleLanguage.chinese]!.status,
          SubtitleMatchStatus.missing,
        );
        expect(
          after[SubtitleLanguage.chinese]!.selectedSourceName,
          'lesson.zh-TW.srt',
        );
      },
    );
  });

  group('SubtitleLanguageDetector', () {
    const detector = SubtitleLanguageDetector();

    test('detects single-language files from script content', () {
      expect(
        detector.detect(
          sourceName: 'lesson.srt',
          cues: const [
            SubtitleCue(
              id: 'en',
              sequence: 1,
              startMs: 1000,
              endMs: 2500,
              text: 'A sentence to learn.',
            ),
          ],
        ),
        'en',
      );
      expect(
        detector.detect(
          sourceName: 'lesson.srt',
          cues: const [
            SubtitleCue(
              id: 'zh',
              sequence: 1,
              startMs: 1000,
              endMs: 2500,
              text: '這是一句中文字幕。',
            ),
          ],
        ),
        'zh-TW',
      );
    });

    test('uses explicit filename language when script alone is mixed', () {
      expect(
        detector.detect(
          sourceName: 'lesson.zh-TW.srt',
          cues: const [
            SubtitleCue(
              id: 'mixed',
              sequence: 1,
              startMs: 1000,
              endMs: 2500,
              text: 'AI 幫助學習。',
            ),
          ],
        ),
        'zh-TW',
      );
    });

    test(
      'returns unknown for mixed-language text it cannot classify safely',
      () {
        expect(
          detector.detect(
            sourceName: 'lesson.srt',
            cues: const [
              SubtitleCue(
                id: 'mixed',
                sequence: 1,
                startMs: 1000,
                endMs: 2500,
                text: 'Learn English 學習中文',
              ),
            ],
          ),
          isNull,
        );
      },
    );
  });

  group('BilingualSubtitleSplitter', () {
    const splitter = BilingualSubtitleSplitter();

    test('joins wrapped lines while splitting a bilingual cue', () {
      final pair = splitter.split(const [
        SubtitleCue(
          id: 'cue-0',
          sequence: 7,
          startMs: 1000,
          endMs: 2500,
          text: 'This is a long English line\nthat wraps.\n這是一句\n換行的中文。',
        ),
      ]);

      expect(
        pair?.english.single.text,
        'This is a long English line\nthat wraps.',
      );
      expect(pair?.chinese.single.text, '這是一句\n換行的中文。');
    });

    test('keeps English names and terms in the Chinese translation track', () {
      final pair = splitter.split(const [
        SubtitleCue(
          id: 'cue-25',
          sequence: 25,
          startMs: 1000,
          endMs: 3000,
          text:
              'Specifically the work by researchers Haselton and Buss.\n'
              '特別是研究者 Haselton 與 Buss 關於錯誤管理理論的工作。',
        ),
        SubtitleCue(
          id: 'cue-54',
          sequence: 54,
          startMs: 3000,
          endMs: 5000,
          text:
              'The terms are false positive and false negative.\n'
              '在文獻中，它們叫做 false positive（偽陽性）和 '
              'false negative（偽陰性）。',
        ),
      ]);

      expect(pair?.english.map((cue) => cue.text), [
        'Specifically the work by researchers Haselton and Buss.',
        'The terms are false positive and false negative.',
      ]);
      expect(pair?.chinese.map((cue) => cue.text), [
        '特別是研究者 Haselton 與 Buss 關於錯誤管理理論的工作。',
        '在文獻中，它們叫做 false positive（偽陽性）和 false negative（偽陰性）。',
      ]);
    });

    test('keeps untranslated cues in a mostly bilingual file', () {
      final pair = splitter.split(const [
        SubtitleCue(
          id: 'cue-1',
          sequence: 1,
          startMs: 0,
          endMs: 1000,
          text: 'The first English line.\n第一句中文。',
        ),
        SubtitleCue(
          id: 'cue-2',
          sequence: 2,
          startMs: 1000,
          endMs: 2000,
          text: 'The second English line.\n第二句中文。',
        ),
        SubtitleCue(
          id: 'cue-3',
          sequence: 3,
          startMs: 2000,
          endMs: 3000,
          text: '這句翻譯保留 Harvard 這個英文名稱。',
        ),
      ]);

      expect(pair?.english.map((cue) => cue.text), [
        'The first English line.',
        'The second English line.',
      ]);
      expect(pair?.chinese.map((cue) => cue.text), [
        '第一句中文。',
        '第二句中文。',
        '這句翻譯保留 Harvard 這個英文名稱。',
      ]);
    });

    test(
      'requires at least half the cues to have distinct bilingual lines',
      () {
        expect(
          splitter.split(const [
            SubtitleCue(
              id: 'bilingual',
              sequence: 1,
              startMs: 0,
              endMs: 1000,
              text: 'A bilingual line.\n雙語字幕。',
            ),
            SubtitleCue(
              id: 'english-1',
              sequence: 2,
              startMs: 1000,
              endMs: 2000,
              text: 'English only.',
            ),
            SubtitleCue(
              id: 'english-2',
              sequence: 3,
              startMs: 2000,
              endMs: 3000,
              text: 'Also English only.',
            ),
          ]),
          isNull,
        );
      },
    );

    test('keeps ordinary multiline single-language cues intact', () {
      expect(
        splitter.split(const [
          SubtitleCue(
            id: 'en',
            sequence: 1,
            startMs: 1000,
            endMs: 2500,
            text: 'A long subtitle line\ncontinues on the next line',
          ),
        ]),
        isNull,
      );
    });
  });

  group('SubtitleAligner', () {
    const aligner = SubtitleAligner();
    const englishA = SubtitleCue(
      id: 'en-a',
      sequence: 1,
      startMs: 10000,
      endMs: 13000,
      text: 'One.',
    );
    const englishB = SubtitleCue(
      id: 'en-b',
      sequence: 9,
      startMs: 13000,
      endMs: 17000,
      text: 'Two.',
    );
    const chinese = SubtitleCue(
      id: 'zh-a',
      sequence: 2,
      startMs: 10000,
      endMs: 17000,
      text: '一、二。',
    );

    test('maps two English sentences to one Chinese cue by overlap', () {
      final alignments = aligner.align(
        sourceCues: const [englishA, englishB],
        targetCues: const [chinese],
      );
      expect(alignments.map((entry) => entry.targetCueIds), [
        ['zh-a'],
        ['zh-a'],
      ]);
      expect(alignments.first.overlapMs['zh-a'], 3000);
      expect(alignments.last.overlapMs['zh-a'], 4000);
    });

    test('applies independent subtitle offsets before overlap matching', () {
      const source = SubtitleCue(
        id: 'en',
        sequence: 1,
        startMs: 5000,
        endMs: 7000,
        text: 'Hello',
      );
      const target = SubtitleCue(
        id: 'zh',
        sequence: 1,
        startMs: 5500,
        endMs: 7500,
        text: '你好',
      );
      final shifted = aligner.align(
        sourceCues: const [source],
        targetCues: const [target],
        sourceOffsetMs: 500,
      );
      expect(shifted.single.targetCueIds, ['zh']);
      expect(shifted.single.overlapMs['zh'], 2000);
    });

    test(
      'supports overlapping target cues, no translation and many-to-one',
      () {
        const first = SubtitleCue(
          id: 'zh-1',
          sequence: 1,
          startMs: 0,
          endMs: 1000,
          text: 'A',
        );
        const second = SubtitleCue(
          id: 'zh-2',
          sequence: 2,
          startMs: 500,
          endMs: 1500,
          text: 'B',
        );
        const en = SubtitleCue(
          id: 'en',
          sequence: 5,
          startMs: 0,
          endMs: 1500,
          text: 'A B',
        );
        final result = aligner.align(
          sourceCues: const [en],
          targetCues: const [second, first],
        );
        expect(result.single.targetCueIds, ['zh-1', 'zh-2']);
        expect(
          aligner.align(sourceCues: const [englishA], targetCues: const []),
          [
            isA<SubtitleAlignment>().having(
              (a) => a.targetCueIds,
              'targets',
              isEmpty,
            ),
          ],
        );
      },
    );
  });

  group('SubtitleSynchronizer', () {
    test('uses half-open intervals and the defined offset direction', () {
      const cue = SubtitleCue(
        id: 'a',
        sequence: 1,
        startMs: 1000,
        endMs: 2000,
        text: 'A',
      );
      final sync = SubtitleSynchronizer(cues: const [cue], offsetMs: 500);
      expect(sync.at(1499), isNull);
      expect(sync.at(1500), cue);
      expect(sync.at(2499), cue);
      expect(sync.at(2500), isNull);
    });

    test(
      'chooses the previous active cue on overlap, then a stable fallback',
      () {
        const earlier = SubtitleCue(
          id: 'early',
          sequence: 1,
          startMs: 0,
          endMs: 5000,
          text: 'Early',
        );
        const later = SubtitleCue(
          id: 'late',
          sequence: 2,
          startMs: 1000,
          endMs: 3000,
          text: 'Late',
        );
        final sync = SubtitleSynchronizer(cues: const [earlier, later]);
        expect(sync.at(2000)?.id, 'late');
        expect(sync.at(2000, previousCueId: 'early')?.id, 'early');
        expect(sync.at(5000), isNull);
      },
    );

    test('locates cues in a 10,000 cue track for repeated random seeks', () {
      final cues = List.generate(
        10000,
        (index) => SubtitleCue(
          id: 'cue-$index',
          sequence: index * 3 + 1,
          startMs: index * 2000,
          endMs: index * 2000 + 1000,
          text: 'Text $index',
        ),
      );
      final sync = SubtitleSynchronizer(cues: cues);
      final watch = Stopwatch()..start();
      for (var index = 0; index < 10000; index++) {
        final cueIndex = (index * 7919) % cues.length;
        expect(sync.at(cueIndex * 2000 + 500)?.id, 'cue-$cueIndex');
      }
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });
}
