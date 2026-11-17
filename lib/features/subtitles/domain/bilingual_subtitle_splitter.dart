import 'subtitle_models.dart';

/// Splits one cue-per-language bilingual SRT into paired subtitle cues.
///
/// The split is accepted only when every cue has exactly two non-empty lines:
/// an English line followed by a line containing Han characters. This keeps
/// ordinary multi-line subtitles intact and leaves the original SRT bytes in
/// each generated track for lossless recovery.
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
      if (lines.length != 2 ||
          !_latin.hasMatch(lines.first) ||
          _han.hasMatch(lines.first) ||
          !_han.hasMatch(lines.last)) {
        return null;
      }
      english.add(
        SubtitleCue(
          id: '${cue.id}-en',
          sequence: cue.sequence,
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: lines.first,
        ),
      );
      chinese.add(
        SubtitleCue(
          id: '${cue.id}-zh',
          sequence: cue.sequence,
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: lines.last,
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
