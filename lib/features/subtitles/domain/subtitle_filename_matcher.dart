import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

enum SubtitleLanguage { english, chinese }

enum SubtitleMatchStatus { missing, matched, ambiguous, manual }

final class SubtitleLanguageMatch {
  SubtitleLanguageMatch({
    required List<String> candidates,
    required this.selectedSourceName,
    required this.status,
  }) : candidates = List.unmodifiable(candidates);

  final List<String> candidates;
  final String? selectedSourceName;
  final SubtitleMatchStatus status;

  bool get requiresUserChoice => status == SubtitleMatchStatus.ambiguous;
}

final class SubtitleFilenameMatcher {
  const SubtitleFilenameMatcher();

  static final RegExp _languageSuffix = RegExp(
    r'^(.*?)[._-](en(?:-[a-z0-9]+)?|zh(?:-[a-z0-9]+)?|english|chinese)\.srt$',
    caseSensitive: false,
  );

  Map<SubtitleLanguage, SubtitleLanguageMatch> match({
    required String audioFileName,
    required Iterable<String> subtitleFileNames,
    Map<SubtitleLanguage, String> manualSelections = const {},
  }) {
    final audioStem = _normalize(p.basenameWithoutExtension(audioFileName));
    final candidates = <SubtitleLanguage, List<String>>{
      for (final language in SubtitleLanguage.values) language: <String>[],
    };

    for (final fileName in subtitleFileNames) {
      final baseName = p.basename(fileName);
      final match = _languageSuffix.firstMatch(_normalize(baseName));
      if (match == null || _normalize(match.group(1)!) != audioStem) continue;
      final language = _languageFrom(match.group(2)!);
      candidates[language]!.add(baseName);
    }

    return Map.unmodifiable({
      for (final language in SubtitleLanguage.values)
        language: _resolve(
          candidates[language]!..sort((a, b) => a.compareTo(b)),
          manualSelections[language],
        ),
    });
  }

  String _normalize(String value) => unorm.nfc(value).toLowerCase();

  SubtitleLanguage _languageFrom(String suffix) =>
      suffix.toLowerCase().startsWith('en') || suffix.toLowerCase() == 'english'
      ? SubtitleLanguage.english
      : SubtitleLanguage.chinese;

  SubtitleLanguageMatch _resolve(List<String> candidates, String? manual) {
    if (manual != null) {
      return SubtitleLanguageMatch(
        candidates: candidates,
        selectedSourceName: manual,
        status: SubtitleMatchStatus.manual,
      );
    }
    if (candidates.isEmpty) {
      return SubtitleLanguageMatch(
        candidates: candidates,
        selectedSourceName: null,
        status: SubtitleMatchStatus.missing,
      );
    }
    if (candidates.length > 1) {
      return SubtitleLanguageMatch(
        candidates: candidates,
        selectedSourceName: null,
        status: SubtitleMatchStatus.ambiguous,
      );
    }
    return SubtitleLanguageMatch(
      candidates: candidates,
      selectedSourceName: candidates.single,
      status: SubtitleMatchStatus.matched,
    );
  }
}
