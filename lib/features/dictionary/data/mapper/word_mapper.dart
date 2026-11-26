import '../../domain/word.dart';
import '../model/word_response_dto.dart';

extension WordDtoMapper on Word {
  WordResponseDto toDto() => WordResponseDto(
    word: word,
    pronunciations: PronunciationsDto(
      uk: pronunciations.uk,
      us: pronunciations.us,
      phonetic: pronunciations.phonetic,
    ),
    entries: [
      for (final entry in entries)
        EntryDto(
          partOfSpeech: entry.partOfSpeech,
          definitions: [
            for (final definition in entry.definitions)
              DefinitionDto(
                enDefinition: definition.enDefinition,
                zhDefinition: definition.zhDefinition,
                examples: [
                  for (final example in definition.examples)
                    ExampleDto(
                      exampleText: example.text,
                      source: example.source,
                      author: example.author,
                      sourceUrl: example.sourceUrl,
                      licenseUrl: example.licenseUrl,
                      matchType: example.matchType,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

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
                        .map(
                          (example) => WordExample(
                            text: example.exampleText,
                            source: example.source,
                            author: example.author,
                            sourceUrl: example.sourceUrl,
                            licenseUrl: example.licenseUrl,
                            matchType: example.matchType,
                          ),
                        )
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
  );
}
