import 'dart:typed_data';

enum SubtitleSelectionMode { automatic, manual }

final class SubtitleCue {
  const SubtitleCue({
    required this.id,
    required this.sequence,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  /// Stable only within this parsed source; it is not derived from SRT sequence.
  final String id;
  final int sequence;
  final int startMs;
  final int endMs;
  final String text;
}

final class SubtitleTrack {
  SubtitleTrack({
    required this.id,
    required this.ownerId,
    required this.materialId,
    required this.languageTag,
    required this.sourceName,
    required List<int> originalBytes,
    required this.revision,
    required this.offsetMs,
    required this.selectionMode,
    required this.isSelected,
    required List<SubtitleCue> cues,
  }) : _originalBytes = Uint8List.fromList(originalBytes),
       cues = List.unmodifiable(cues);

  final String id;
  final String ownerId;
  final String materialId;
  final String languageTag;
  final String sourceName;
  final Uint8List _originalBytes;

  /// Exact source bytes, including BOM and line endings.
  Uint8List get originalBytes => Uint8List.fromList(_originalBytes);

  final int revision;
  final int offsetMs;
  final SubtitleSelectionMode selectionMode;
  final bool isSelected;
  final List<SubtitleCue> cues;

  SubtitleTrack copyWith({
    int? offsetMs,
    SubtitleSelectionMode? selectionMode,
    bool? isSelected,
  }) => SubtitleTrack(
    id: id,
    ownerId: ownerId,
    materialId: materialId,
    languageTag: languageTag,
    sourceName: sourceName,
    originalBytes: _originalBytes,
    revision: revision,
    offsetMs: offsetMs ?? this.offsetMs,
    selectionMode: selectionMode ?? this.selectionMode,
    isSelected: isSelected ?? this.isSelected,
    cues: cues,
  );
}

final class SubtitleAlignment {
  const SubtitleAlignment({
    required this.sourceCueId,
    required this.targetCueIds,
    required this.overlapMs,
  });

  final String sourceCueId;
  final List<String> targetCueIds;
  final Map<String, int> overlapMs;
}
