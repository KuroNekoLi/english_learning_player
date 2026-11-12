import 'bookmark.dart';
import '../../subtitles/domain/subtitle_models.dart';

/// Relocates a saved cue to the currently selected track without changing the
/// original bookmark anchor.
final class BookmarkResolver {
  const BookmarkResolver({this.minimumOverlapRatio = 0.5});

  final double minimumOverlapRatio;

  BookmarkResolution resolve(Bookmark bookmark, List<SubtitleTrack> tracks) {
    final candidates = <_Candidate>[
      for (final track in tracks)
        if (track.isSelected &&
            _languageFamily(track.languageTag) ==
                _languageFamily(bookmark.anchor.languageTag))
          for (final cue in track.cues) _Candidate(track: track, cue: cue),
    ];
    if (candidates.isEmpty) return const BookmarkResolution.missing();

    final exact = candidates.where((candidate) {
      final track = candidate.track;
      final cue = candidate.cue;
      return track.id == bookmark.anchor.trackId &&
          track.revision == bookmark.anchor.trackRevision &&
          cue.id == bookmark.anchor.cueId;
    }).toList();
    if (exact.length == 1) return _resolved(exact.single);
    if (exact.length > 1) return const BookmarkResolution.ambiguous();

    final anchorText = _normalize(bookmark.anchor.cueText);
    final textMatches = candidates
        .where((candidate) => _normalize(candidate.cue.text) == anchorText)
        .toList();
    if (textMatches.isNotEmpty) {
      return _resolveRanked(textMatches, bookmark.anchor);
    }

    final overlapping = candidates.where((candidate) {
      final overlap = _overlap(
        candidate.audioStartMs,
        candidate.audioEndMs,
        bookmark.anchor.startMs,
        bookmark.anchor.endMs,
      );
      final candidateLength = candidate.audioEndMs - candidate.audioStartMs;
      final anchorLength = bookmark.anchor.endMs - bookmark.anchor.startMs;
      final shorterLength = candidateLength < anchorLength
          ? candidateLength
          : anchorLength;
      return shorterLength > 0 &&
          overlap / shorterLength >= minimumOverlapRatio;
    }).toList();
    if (overlapping.isEmpty) return const BookmarkResolution.missing();
    return _resolveRanked(overlapping, bookmark.anchor);
  }

  BookmarkResolution _resolveRanked(
    List<_Candidate> candidates,
    BookmarkCueAnchor anchor,
  ) {
    final ranked = candidates
      ..sort((left, right) {
        final overlap =
            _overlap(
              right.audioStartMs,
              right.audioEndMs,
              anchor.startMs,
              anchor.endMs,
            ).compareTo(
              _overlap(
                left.audioStartMs,
                left.audioEndMs,
                anchor.startMs,
                anchor.endMs,
              ),
            );
        if (overlap != 0) return overlap;
        final distance = _midpointDistance(
          left,
          anchor,
        ).compareTo(_midpointDistance(right, anchor));
        if (distance != 0) return distance;
        final byStart = left.audioStartMs.compareTo(right.audioStartMs);
        return byStart != 0 ? byStart : left.cue.id.compareTo(right.cue.id);
      });

    if (ranked.length > 1 &&
        _overlap(
              ranked[0].audioStartMs,
              ranked[0].audioEndMs,
              anchor.startMs,
              anchor.endMs,
            ) ==
            _overlap(
              ranked[1].audioStartMs,
              ranked[1].audioEndMs,
              anchor.startMs,
              anchor.endMs,
            ) &&
        _midpointDistance(ranked[0], anchor) ==
            _midpointDistance(ranked[1], anchor)) {
      return const BookmarkResolution.ambiguous();
    }
    return _resolved(ranked.first);
  }

  BookmarkResolution _resolved(_Candidate candidate) =>
      BookmarkResolution.resolved(track: candidate.track, cue: candidate.cue);

  String _languageFamily(String tag) => tag.toLowerCase().split('-').first;

  String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  int _overlap(int start, int end, int otherStart, int otherEnd) {
    final overlap =
        (end < otherEnd ? end : otherEnd) -
        (start > otherStart ? start : otherStart);
    return overlap > 0 ? overlap : 0;
  }

  int _midpointDistance(_Candidate candidate, BookmarkCueAnchor anchor) =>
      ((candidate.audioStartMs + candidate.audioEndMs) -
              (anchor.startMs + anchor.endMs))
          .abs();
}

final class _Candidate {
  const _Candidate({required this.track, required this.cue});

  final SubtitleTrack track;
  final SubtitleCue cue;

  int get audioStartMs => cue.startMs + track.offsetMs;
  int get audioEndMs => cue.endMs + track.offsetMs;
}
