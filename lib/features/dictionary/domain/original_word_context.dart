/// A snapshot of the subtitle line that led to saving a dictionary word.
final class OriginalWordContext {
  const OriginalWordContext({
    required this.materialId,
    required this.materialTitle,
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.translations,
    this.version = 1,
  });

  final int version;
  final String materialId;
  final String materialTitle;
  final int startMs;
  final int endMs;
  final String english;
  final List<String> translations;

  bool get isPlayableRange => startMs >= 0 && endMs > startMs;

  Map<String, Object?> toJson() => {
    'version': version,
    'materialId': materialId,
    'materialTitle': materialTitle,
    'startMs': startMs,
    'endMs': endMs,
    'english': english,
    'translations': translations,
  };

  static OriginalWordContext? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final materialId = value['materialId'];
    final materialTitle = value['materialTitle'];
    final startMs = value['startMs'];
    final endMs = value['endMs'];
    final english = value['english'];
    final rawTranslations = value['translations'];
    if (value['version'] != 1 ||
        materialId is! String ||
        materialId.isEmpty ||
        materialTitle is! String ||
        startMs is! int ||
        endMs is! int ||
        english is! String ||
        english.trim().isEmpty ||
        rawTranslations is! List) {
      return null;
    }
    final translations = <String>[];
    for (final translation in rawTranslations) {
      if (translation is! String) return null;
      if (translation.trim().isNotEmpty) translations.add(translation.trim());
    }
    return OriginalWordContext(
      materialId: materialId,
      materialTitle: materialTitle,
      startMs: startMs,
      endMs: endMs,
      english: english.trim(),
      translations: List.unmodifiable(translations),
    );
  }
}
