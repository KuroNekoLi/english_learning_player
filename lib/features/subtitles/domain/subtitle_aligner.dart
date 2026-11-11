import 'subtitle_models.dart';

final class SubtitleAligner {
  const SubtitleAligner({this.minimumShorterCueCoverage = 0.25})
    : assert(minimumShorterCueCoverage >= 0),
      assert(minimumShorterCueCoverage <= 1);

  /// The overlap must cover at least this fraction of the shorter cue.
  final double minimumShorterCueCoverage;

  List<SubtitleAlignment> align({
    required List<SubtitleCue> sourceCues,
    required List<SubtitleCue> targetCues,
    int sourceOffsetMs = 0,
    int targetOffsetMs = 0,
  }) {
    final sortedTargets = targetCues.toList()
      ..sort((a, b) {
        final byStart = a.startMs.compareTo(b.startMs);
        if (byStart != 0) return byStart;
        final byEnd = a.endMs.compareTo(b.endMs);
        return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
      });
    final prefixMaximumEnd = <int>[];
    var maximumEnd = -1;
    for (final cue in sortedTargets) {
      if (cue.endMs > maximumEnd) maximumEnd = cue.endMs;
      prefixMaximumEnd.add(maximumEnd);
    }

    return List.unmodifiable(
      sourceCues.map((source) {
        final sourceStart = source.startMs - sourceOffsetMs;
        final sourceEnd = source.endMs - sourceOffsetMs;
        final matches = <({SubtitleCue cue, int overlap})>[];
        var index = _firstGreaterThan(
          prefixMaximumEnd,
          sourceStart + targetOffsetMs,
        );
        final afterMatches = _firstAtLeastStart(
          sortedTargets,
          sourceEnd + targetOffsetMs,
        );
        while (index < afterMatches) {
          final target = sortedTargets[index];
          final targetStart = target.startMs - targetOffsetMs;
          final targetEnd = target.endMs - targetOffsetMs;
          final overlap = _overlap(
            sourceStart,
            sourceEnd,
            targetStart,
            targetEnd,
          );
          final shorterDuration = (sourceEnd - sourceStart).clamp(
            1,
            0x7fffffffffffffff,
          );
          final targetDuration = (targetEnd - targetStart).clamp(
            1,
            0x7fffffffffffffff,
          );
          final minimumDuration = shorterDuration < targetDuration
              ? shorterDuration
              : targetDuration;
          if (overlap > 0 &&
              overlap / minimumDuration >= minimumShorterCueCoverage) {
            matches.add((cue: target, overlap: overlap));
          }
          index++;
        }
        matches.sort((a, b) {
          final byOverlap = b.overlap.compareTo(a.overlap);
          if (byOverlap != 0) return byOverlap;
          final byStart = a.cue.startMs.compareTo(b.cue.startMs);
          return byStart != 0 ? byStart : a.cue.id.compareTo(b.cue.id);
        });
        return SubtitleAlignment(
          sourceCueId: source.id,
          targetCueIds: List.unmodifiable(matches.map((item) => item.cue.id)),
          overlapMs: Map.unmodifiable({
            for (final item in matches) item.cue.id: item.overlap,
          }),
        );
      }),
    );
  }

  int _overlap(int aStart, int aEnd, int bStart, int bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : 0;
  }

  int _firstGreaterThan(List<int> values, int value) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle] > value) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  int _firstAtLeastStart(List<SubtitleCue> cues, int startMs) {
    var low = 0;
    var high = cues.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (cues[middle].startMs < startMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
