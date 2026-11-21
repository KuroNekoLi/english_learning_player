import 'package:path/path.dart' as p;

import 'subtitle_models.dart';

/// Detects a supported single-language SRT when it is not a bilingual pair.
///
/// Bilingual cues should be split by [BilingualSubtitleSplitter] first. This
/// detector deliberately returns null for mixed scripts that cannot be split
/// confidently instead of silently assigning the wrong language.
final class SubtitleLanguageDetector {
  const SubtitleLanguageDetector();

  static final RegExp _han = RegExp(r'[\u3400-\u9FFF]');
  static final RegExp _latin = RegExp(r'[A-Za-z]');
  static final RegExp _taggedName = RegExp(
    r'[._-](en(?:-[a-z0-9]+)?|zh(?:-[a-z0-9]+)?|english|chinese)\.srt$',
    caseSensitive: false,
  );

  String? detect({
    required String sourceName,
    required List<SubtitleCue> cues,
  }) {
    final suffix = _taggedName.firstMatch(p.basename(sourceName))?.group(1);
    if (suffix != null) return _tagToLanguage(suffix);

    var hanCount = 0;
    var latinCount = 0;
    for (final cue in cues) {
      hanCount += _han.allMatches(cue.text).length;
      latinCount += _latin.allMatches(cue.text).length;
    }
    if (hanCount == 0 && latinCount == 0) return null;
    if (hanCount == 0) return 'en';
    if (latinCount == 0) return 'zh-TW';

    // Allow occasional names or acronyms in an otherwise single-language file.
    if (hanCount >= latinCount * 4) return 'zh-TW';
    if (latinCount >= hanCount * 4) return 'en';
    return null;
  }

  String _tagToLanguage(String tag) =>
      tag.toLowerCase().startsWith('zh') || tag.toLowerCase() == 'chinese'
      ? 'zh-TW'
      : 'en';
}
