import 'subtitle_models.dart';
import 'subtitle_time.dart';

/// Resolves half-open cue intervals with O(log n + overlapping cues) lookups.
final class SubtitleSynchronizer {
  SubtitleSynchronizer({required List<SubtitleCue> cues, this.offsetMs = 0})
    : _cues = List.unmodifiable(_sort(cues)) {
    var maximumEnd = -1;
    for (final cue in _cues) {
      if (cue.endMs > maximumEnd) maximumEnd = cue.endMs;
      _prefixMaxEnd.add(maximumEnd);
    }
  }

  final List<SubtitleCue> _cues;
  final int offsetMs;
  final List<int> _prefixMaxEnd = [];

  SubtitleCue? at(int positionMs, {String? previousCueId}) {
    final subtitleTimeMs = audioToSubtitleMs(positionMs, offsetMs);
    if (subtitleTimeMs < 0 || _cues.isEmpty) return null;

    var low = 0;
    var high = _cues.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_cues[middle].startMs <= subtitleTimeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var index = low - 1;
    final active = <SubtitleCue>[];
    while (index >= 0 && _prefixMaxEnd[index] > subtitleTimeMs) {
      final cue = _cues[index];
      if (cue.startMs <= subtitleTimeMs && subtitleTimeMs < cue.endMs) {
        active.add(cue);
      }
      index--;
    }
    if (active.isEmpty) return null;
    for (final cue in active) {
      if (cue.id == previousCueId) return cue;
    }
    active.sort((a, b) {
      final byStart = b.startMs.compareTo(a.startMs);
      if (byStart != 0) return byStart;
      final byEnd = a.endMs.compareTo(b.endMs);
      return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
    });
    return active.first;
  }

  static List<SubtitleCue> _sort(List<SubtitleCue> cues) =>
      cues.toList()..sort((a, b) {
        final byStart = a.startMs.compareTo(b.startMs);
        if (byStart != 0) return byStart;
        final byEnd = a.endMs.compareTo(b.endMs);
        return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
      });
}
