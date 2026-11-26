/// Dictionary data shape reused from BlackCatNews at commit
/// 578c2caed20b48fe262c67e43d5bfa50a7661720.
final class Word {
  const Word({
    required this.word,
    required this.pronunciations,
    required this.entries,
  });

  final String word;
  final WordPronunciations pronunciations;
  final List<WordEntry> entries;
}

final class WordPronunciations {
  const WordPronunciations({this.uk, this.us, this.phonetic});

  final String? uk;
  final String? us;
  final String? phonetic;
}

final class WordEntry {
  const WordEntry({required this.partOfSpeech, required this.definitions});

  final String partOfSpeech;
  final List<WordDefinition> definitions;
}

final class WordDefinition {
  const WordDefinition({
    required this.enDefinition,
    required this.zhDefinition,
    required this.examples,
  });

  final String enDefinition;
  final String zhDefinition;
  final List<WordExample> examples;
}

final class WordExample {
  const WordExample({
    required this.text,
    this.source,
    this.author,
    this.sourceUrl,
    this.licenseUrl,
    this.matchType,
  });

  final String text;
  final String? source;
  final String? author;
  final String? sourceUrl;
  final String? licenseUrl;
  final String? matchType;
}
