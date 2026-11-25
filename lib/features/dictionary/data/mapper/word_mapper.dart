import '../../domain/word.dart';
import '../model/word_response_dto.dart';

extension WordResponseMapper on WordResponseDto {
  Word toDomain() => Word(
    word: word,
    pronunciations: WordPronunciations(
      uk: pronunciations.uk,
      us: pronunciations.us,
      phonetic: pronunciations.phonetic,
    ),
    entries: entries
        .map(
          (entry) => WordEntry(
            partOfSpeech: entry.partOfSpeech,
            definitions: entry.definitions
                .map(
                  (definition) => WordDefinition(
                    enDefinition: definition.enDefinition,
                    zhDefinition: definition.zhDefinition,
                    examples: definition.examples
                        .map((example) => example.exampleText)
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
  );
}
