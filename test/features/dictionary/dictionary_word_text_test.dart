import 'package:english_learning_player/features/dictionary/widgets/dictionary_word_text.dart';
import 'package:english_learning_player/features/dictionary/data/dictionary_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:english_learning_player/features/dictionary/domain/word.dart';
import 'package:english_learning_player/features/dictionary/dictionary_dependencies.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap resolves one full word and highlights that token', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DictionaryWordText(
              text: 'A traveler asked for directions.',
              style: const TextStyle(fontSize: 20),
              lookupOnTap: false,
              onWordSelected: (word) => selected = word,
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
    await tester.tapAt(
      Offset(textBox.left + prefix.width + 8, textBox.center.dy),
    );
    await tester.pump();

    expect(selected, 'asked');
    final richText = tester.widget<RichText>(find.byType(RichText).last);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWith(
            (ref) async => _FixtureDictionaryRepository(),
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
    await tester.tapAt(
      Offset(textBox.left + prefix.width + 8, textBox.center.dy),
    );
    await tester.pumpAndSettle();

    expect(find.text('英 /ɪɡˈzɑːmpəl/  ·  美 /ɪɡˈzæmpəl/'), findsOneWidget);
    expect(
      find.text('例子；實例\nA thing characteristic of its kind.'),
      findsOneWidget,
    );
    expect(find.text('“This is a good example.”'), findsOneWidget);
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
        ],
        child: const MaterialApp(
          home: Scaffold(
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
    await tester.tapAt(Offset(rect.left + prefix.width + 8, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.text("音標 hә'lәu"), findsOneWidget);
    expect(find.text('喂, 嘿'), findsOneWidget);
    expect(find.text('喂, 嘿\n'), findsNothing);
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
            examples: ['This is a good example.'],
          ),
        ],
      ),
    ],
  );
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
