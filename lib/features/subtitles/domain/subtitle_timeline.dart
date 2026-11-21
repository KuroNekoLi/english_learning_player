import 'bilingual_subtitle_splitter.dart';
import 'subtitle_aligner.dart';
import 'subtitle_models.dart';

typedef SubtitleLine = ({
  SubtitleCue cue,
  String english,
  List<SubtitleCue> translations,
});

/// Immutable presentation data for one selection of subtitle tracks.
final class SubtitleTimeline {
  SubtitleTimeline(SubtitleTrack english, SubtitleTrack? chinese)
    : offsetMs = english.offsetMs,
      hasChineseTrack = chinese != null,
      lines = _buildLines(english, chinese) {
    _indexById = {for (var i = 0; i < lines.length; i++) lines[i].cue.id: i};
  }

  final int offsetMs;
  final bool hasChineseTrack;
  final List<SubtitleLine> lines;
  late final Map<String, int> _indexById;

  int? indexOf(String cueId) => _indexById[cueId];

  List<SubtitleCue> translationsFor(String cueId) {
    final index = indexOf(cueId);
    return index == null ? const [] : lines[index].translations;
  }

  static List<SubtitleLine> _buildLines(
    SubtitleTrack english,
    SubtitleTrack? chinese,
  ) {
    final cues = english.cues.toList()
      ..sort((a, b) {
        final byTime = a.startMs.compareTo(b.startMs);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final chineseById = {
      for (final cue in chinese?.cues ?? const <SubtitleCue>[]) cue.id: cue,
    };
    final matches = chinese == null
        ? const <SubtitleAlignment>[]
        : const SubtitleAligner().align(
            sourceCues: cues,
            targetCues: chinese.cues,
            sourceOffsetMs: english.offsetMs,
            targetOffsetMs: chinese.offsetMs,
          );
    final byEnglishId = {
      for (final match in matches)
        match.sourceCueId: match.targetCueIds
            .map((id) => chineseById[id]!)
            .toList(),
    };
    return List.unmodifiable(
      cues.map((cue) {
        final inline = const BilingualSubtitleSplitter().split([cue]);
        final aligned = byEnglishId[cue.id];
        return (
          cue: cue,
          english: inline?.english.single.text ?? cue.text,
          translations: List<SubtitleCue>.unmodifiable(
            aligned != null && aligned.isNotEmpty
                ? aligned
                : inline?.chinese ?? const <SubtitleCue>[],
          ),
        );
      }),
    );
  }
}
