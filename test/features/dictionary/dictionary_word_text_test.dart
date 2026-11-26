import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/speech_playback.dart';
import 'package:english_learning_player/features/dictionary/widgets/dictionary_word_text.dart';
import 'package:english_learning_player/features/dictionary/widgets/word_bank_page.dart';
import 'package:english_learning_player/features/dictionary/data/dictionary_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:english_learning_player/features/dictionary/domain/word.dart';
import 'package:english_learning_player/features/dictionary/dictionary_dependencies.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';

import '../../fakes/fake_audio_engine.dart';

void main() {
  testWidgets('can save from lookup and remove from the word bank detail', (
    tester,
  ) async {
    final words = <Word>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWith(
            (ref) async => _EcdictDictionaryRepository(),
          ),
          savedDictionaryWordsProvider.overrideWith(
            (ref) async => List.of(words),
          ),
          updateSavedDictionaryWordProvider.overrideWith((ref) {
            return (word, {required save}) async {
              if (save) {
                words.add(word);
              } else {
                words.removeWhere((saved) => saved.word == word.word);
              }
              ref.invalidate(savedDictionaryWordsProvider);
            };
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [OpenWordBankButton()]),
            body: const Center(
              child: DictionaryWordText(
                text: 'hello',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入單字庫'));
    await tester.pumpAndSettle();
    expect(find.text('已加入單字庫 · 移除'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉單字查詢'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('我的單字庫'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'hello'));
    await tester.pumpAndSettle();
    expect(find.text('喂, 嘿'), findsOneWidget);
    await tester.tap(find.text('已加入單字庫 · 移除'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('還沒有收藏單字。可從字典查詢加入。'), findsOneWidget);
  });

  testWidgets('touch taps do not look up; long press highlights one token', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWith(
            (ref) async => _FixtureDictionaryRepository(),
          ),
          savedDictionaryWordsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DictionaryWordText(
                text: 'A traveler asked for directions.',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );

    final textBox = tester.getRect(find.byType(RichText).last);
    final prefix = TextPainter(
      text: const TextSpan(text: 'A traveler ', style: TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(textBox.left + prefix.width + 8, textBox.center.dy);
    await tester.tapAt(offset);
    await tester.pumpAndSettle();
    expect(find.byTooltip('關閉單字查詢'), findsNothing);
    await tester.longPressAt(offset);
    await tester.pumpAndSettle();
    expect(find.text('asked'), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final spans = richText.text as TextSpan;
    final selectedSpan = _textSpans(spans)
        .singleWhere((span) => span.text == 'asked');
    expect(selectedSpan.style?.decoration, TextDecoration.underline);
    expect(selectedSpan.style?.backgroundColor, isNotNull);
  });

  testWidgets('floating lookup shows pronunciation and bilingual meaning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = Uri.parse('file:///fixture.m4a');
    final audio = FakeAudioEngine({source: 10000});
    addTearDown(audio.dispose);
    await audio.load(MediaSource(materialId: 'fixture', uri: source));
    await audio.play();
    final speech = _RecordingSpeech();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWith(
            (ref) async => _FixtureDictionaryRepository(),
          ),
          savedDictionaryWordsProvider.overrideWith((ref) async => []),
          speechPlaybackProvider.overrideWithValue(
            SpeechPlayback(audio, speech),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DictionaryWordText(
                text: 'A useful example.',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );

    final textBox = tester.getRect(find.byType(RichText).last);
    final prefix = TextPainter(
      text: const TextSpan(text: 'A useful ', style: TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    await tester.longPressAt(
      Offset(textBox.left + prefix.width + 8, textBox.center.dy),
    );
    await tester.pumpAndSettle();

    expect(find.text('英 /ɪɡˈzɑːmpəl/  ·  美 /ɪɡˈzæmpəl/'), findsOneWidget);
    expect(find.text('收錄 2 個詞義'), findsOneWidget);
    expect(
      find.text('1. 例子；實例\nA thing characteristic of its kind.'),
      findsOneWidget,
    );
    expect(find.text('“這是一個好例子。”'), findsOneWidget);
    expect(find.text('2. 模範\nA model to follow.'), findsOneWidget);
    expect(find.text('“她是我們的榜樣。”'), findsOneWidget);
    expect(find.text('Chinese Open Wordnet'), findsOneWidget);
    await tester.tap(find.byTooltip('英式發音'));
    await tester.pumpAndSettle();
    expect(speech.spoken.last, (text: 'example', locale: 'en-GB'));
    expect(audio.snapshot.playing, isFalse);
    await tester.tap(find.byTooltip('朗讀英文例句'));
    await tester.pumpAndSettle();
    expect(speech.spoken.last, (
      text: 'This is a good example.',
      locale: 'en-US',
    ));
    final chineseButton = find.byTooltip('朗讀中文例句').first;
    await tester.ensureVisible(chineseButton);
    await tester.pumpAndSettle();
    await tester.tap(chineseButton);
    await tester.pumpAndSettle();
    expect(speech.spoken.last, (text: '這是一個好例子。', locale: 'zh-TW'));
    await tester.tap(find.byTooltip('關閉單字查詢'));
    await tester.pumpAndSettle();
    expect(speech.stopCount, 3);
  });
  testWidgets('shows ECDICT generic phonetic without empty English text', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWith(
            (ref) async => _EcdictDictionaryRepository(),
          ),
          savedDictionaryWordsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: Center(
              child: DictionaryWordText(
                text: 'A hello world.',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(RichText).last);
    final prefix = TextPainter(
      text: const TextSpan(text: 'A ', style: TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(Offset(rect.left + prefix.width + 8, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('關閉單字查詢'), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text("音標 hә'lәu"), findsOneWidget);
    expect(find.text('喂, 嘿'), findsOneWidget);
    expect(find.text('喂, 嘿\n'), findsNothing);
    await mouse.moveTo(tester.getCenter(find.byTooltip('美式發音')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text("音標 hә'lәu"), findsOneWidget);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byTooltip('關閉單字查詢'), findsNothing);
    await mouse.removePointer();
  });
}

final class _FixtureDictionaryRepository implements DictionaryRepository {
  @override
  Future<Word> lookupWord(String word) async => const Word(
    word: 'example',
    pronunciations: WordPronunciations(uk: '/ɪɡˈzɑːmpəl/', us: '/ɪɡˈzæmpəl/'),
    entries: [
      WordEntry(
        partOfSpeech: 'noun',
        definitions: [
          WordDefinition(
            enDefinition: 'A thing characteristic of its kind.',
            zhDefinition: '例子；實例',
            examples: [WordExample(text: 'This is a good example.\n這是一個好例子。')],
          ),
          WordDefinition(
            enDefinition: 'A model to follow.',
            zhDefinition: '模範',
            examples: [
              WordExample(
                text: '她是我們的榜樣。',
                source: 'Chinese Open Wordnet',
                sourceUrl: 'https://bond-lab.github.io/cow/',
                matchType: 'source_sense',
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final class _RecordingSpeech implements SpeechPort {
  final spoken = <({String text, String locale})>[];
  int stopCount = 0;

  @override
  Future<void> speak(String text, String locale) async =>
      spoken.add((text: text, locale: locale));

  @override
  Future<void> stop() async => stopCount++;
}

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}

final class _EcdictDictionaryRepository implements DictionaryRepository {
  @override
  Future<Word> lookupWord(String word) async => const Word(
    word: 'hello',
    pronunciations: WordPronunciations(phonetic: "hә'lәu"),
    entries: [
      WordEntry(
        partOfSpeech: 'interjection',
        definitions: [
          WordDefinition(enDefinition: '', zhDefinition: '喂, 嘿', examples: []),
        ],
      ),
    ],
  );
}
