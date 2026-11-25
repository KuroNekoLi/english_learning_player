/// DTO for the BlackCatNews Dictionary API's snake_case JSON response.
final class WordResponseDto {
  const WordResponseDto({
    required this.word,
    required this.pronunciations,
    required this.entries,
  });

  final String word;
  final PronunciationsDto pronunciations;
  final List<EntryDto> entries;

  factory WordResponseDto.fromJson(Map<String, dynamic> json) =>
      WordResponseDto(
        word: json['word'] as String,
        pronunciations: PronunciationsDto.fromJson(
          json['pronunciations'] as Map<String, dynamic>,
        ),
        entries: (json['entries'] as List<dynamic>)
            .map((value) => EntryDto.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'word': word,
    'pronunciations': pronunciations.toJson(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

final class PronunciationsDto {
  const PronunciationsDto({this.uk, this.us, this.phonetic});

  final String? uk;
  final String? us;
  final String? phonetic;

  factory PronunciationsDto.fromJson(Map<String, dynamic> json) =>
      PronunciationsDto(
        uk: json['uk'] as String?,
        us: json['us'] as String?,
        phonetic: json['phonetic'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'uk': uk,
    'us': us,
    if (phonetic != null) 'phonetic': phonetic,
  };
}

final class EntryDto {
  const EntryDto({required this.partOfSpeech, required this.definitions});
  final String partOfSpeech;
  final List<DefinitionDto> definitions;

  factory EntryDto.fromJson(Map<String, dynamic> json) => EntryDto(
    partOfSpeech: json['part_of_speech'] as String,
    definitions: (json['definitions'] as List<dynamic>)
        .map((value) => DefinitionDto.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'part_of_speech': partOfSpeech,
    'definitions': definitions
        .map((definition) => definition.toJson())
        .toList(),
  };
}

final class DefinitionDto {
  const DefinitionDto({
    required this.enDefinition,
    required this.zhDefinition,
    required this.examples,
  });

  final String enDefinition;
  final String zhDefinition;
  final List<ExampleDto> examples;

  factory DefinitionDto.fromJson(Map<String, dynamic> json) => DefinitionDto(
    enDefinition: json['en_definition'] as String,
    zhDefinition: json['zh_definition'] as String,
    examples: (json['examples'] as List<dynamic>)
        .map((value) => ExampleDto.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'en_definition': enDefinition,
    'zh_definition': zhDefinition,
    'examples': examples.map((example) => example.toJson()).toList(),
  };
}

final class ExampleDto {
  const ExampleDto({required this.exampleText});
  final String exampleText;

  factory ExampleDto.fromJson(Map<String, dynamic> json) =>
      ExampleDto(exampleText: json['example_text'] as String);

  Map<String, dynamic> toJson() => {'example_text': exampleText};
}
