import 'subtitle_models.dart';

/// Splits one cue-per-language bilingual SRT into paired subtitle cues.
///
/// The split is accepted when every cue has an English section followed by a
/// Chinese section. Chinese lines may contain English names or terms; after
/// the first Han character, remaining lines belong to the Chinese section.
/// Ordinary multi-line subtitles remain a single track, and the original SRT
/// bytes are retained in both generated tracks.
final class BilingualSubtitleSplitter {
  const BilingualSubtitleSplitter();

  static final RegExp _latin = RegExp(r'[A-Za-z]');
  static final RegExp _han = RegExp(r'[\u3400-\u9FFF]');

  BilingualSubtitlePair? split(List<SubtitleCue> cues) {
    if (cues.isEmpty) return null;
    final english = <SubtitleCue>[];
    final chinese = <SubtitleCue>[];

    for (final cue in cues) {
      final lines = cue.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final englishLines = <String>[];
      final chineseLines = <String>[];
      var chineseStarted = false;
      List<String>? lastLanguageLines;
      for (final line in lines) {
        final hasLatin = _latin.hasMatch(line);
        final hasHan = _han.hasMatch(line);
        if (hasHan) {
          chineseStarted = true;
          chineseLines.add(line);
          lastLanguageLines = chineseLines;
        } else if (hasLatin && !chineseStarted) {
          englishLines.add(line);
          lastLanguageLines = englishLines;
        } else if (hasLatin) {
          // Standalone English terms can occur inside a Chinese translation.
          chineseLines.add(line);
          lastLanguageLines = chineseLines;
        } else if (lastLanguageLines != null) {
          lastLanguageLines.add(line);
        } else {
          return null;
        }
      }
      if (englishLines.isEmpty || chineseLines.isEmpty) return null;
      english.add(
        SubtitleCue(
          id: '${cue.id}-en',
          sequence: cue.sequence,
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: englishLines.join('\n'),
        ),
      );
      chinese.add(
        SubtitleCue(
          id: '${cue.id}-zh',
          sequence: cue.sequence,
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: chineseLines.join('\n'),
        ),
      );
    }
    return BilingualSubtitlePair(english: english, chinese: chinese);
  }
}

final class BilingualSubtitlePair {
  BilingualSubtitlePair({
    required List<SubtitleCue> english,
    required List<SubtitleCue> chinese,
  }) : english = List.unmodifiable(english),
       chinese = List.unmodifiable(chinese);

  final List<SubtitleCue> english;
  final List<SubtitleCue> chinese;
}
