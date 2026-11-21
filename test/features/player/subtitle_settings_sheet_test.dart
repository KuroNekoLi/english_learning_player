import 'package:english_learning_player/features/learning/domain/learning_session.dart';
import 'package:english_learning_player/features/player/widgets/subtitle_settings_sheet.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('groups detected bilingual tracks under their source SRT', (
    tester,
  ) async {
    final sourceBytes = 'same original bilingual source'.codeUnits;
    final tracks = [
      _track(
        id: 'lesson-en',
        languageTag: 'en',
        sourceName: 'lesson.srt · EN',
        bytes: sourceBytes,
        cueText: 'A sentence to learn.',
        selected: true,
      ),
      _track(
        id: 'lesson-zh',
        languageTag: 'zh-TW',
        sourceName: 'lesson.srt · 繁中',
        bytes: sourceBytes,
        cueText: '這是一句練習句。',
        selected: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleSettingsSheet(
            tracks: tracks,
            onSelect: (_) {},
            onOffsetChanged: (_, _) async {},
            onImport: () async {},
            visibility: SubtitleVisibility.bilingual,
            onVisibilityChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('匯入 SRT 後會自動辨識單語或雙語字幕來源。'), findsOneWidget);
    expect(find.text('lesson.srt'), findsOneWidget);
    expect(find.text('雙語來源'), findsOneWidget);
    expect(find.text('英文字幕軌'), findsOneWidget);
    expect(find.text('中文字幕軌'), findsOneWidget);
    expect(find.text('沒有可選字幕軌'), findsNothing);
  });

  testWidgets(
    'shows a single-language source without an empty language group',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleSettingsSheet(
              tracks: [
                _track(
                  id: 'lesson-zh',
                  languageTag: 'zh-TW',
                  sourceName: 'lesson.srt',
                  bytes: 'source'.codeUnits,
                  cueText: '只有中文。',
                  selected: true,
                ),
              ],
              onSelect: (_) {},
              onOffsetChanged: (_, _) async {},
              onImport: () async {},
              visibility: SubtitleVisibility.chineseOnly,
              onVisibilityChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('lesson.srt'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('中文字幕軌'), findsOneWidget);
      expect(find.text('英文'), findsNothing);
      expect(find.text('沒有可選字幕軌'), findsNothing);
    },
  );
}

SubtitleTrack _track({
  required String id,
  required String languageTag,
  required String sourceName,
  required List<int> bytes,
  required String cueText,
  required bool selected,
}) => SubtitleTrack(
  id: id,
  ownerId: 'owner-1',
  materialId: 'material-1',
  languageTag: languageTag,
  sourceName: sourceName,
  originalBytes: bytes,
  revision: 1,
  offsetMs: 0,
  selectionMode: SubtitleSelectionMode.manual,
  isSelected: selected,
  cues: [
    SubtitleCue(
      id: '$id-cue',
      sequence: 1,
      startMs: 0,
      endMs: 1000,
      text: cueText,
    ),
  ],
);
