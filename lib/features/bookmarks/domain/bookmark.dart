import '../../subtitles/domain/subtitle_models.dart';

/// Immutable cue snapshot captured when a user bookmarks a sentence.
final class BookmarkCueAnchor {
  const BookmarkCueAnchor({
    required this.trackId,
    required this.trackRevision,
    required this.languageTag,
    required this.cueId,
    required this.cueText,
    required this.startMs,
    required this.endMs,
  }) : assert(trackRevision > 0),
       assert(startMs >= 0),
       assert(endMs > startMs);

  final String trackId;
  final int trackRevision;
  final String languageTag;
  final String cueId;
  final String cueText;

  /// Audio timeline interval, with the track offset already applied.
  final int startMs;
  final int endMs;
}

final class Bookmark {
  const Bookmark({
    required this.id,
    required this.ownerId,
    required this.materialId,
    required this.anchor,
    required this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String ownerId;
  final String materialId;
  final BookmarkCueAnchor anchor;
  final DateTime createdAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

enum BookmarkResolutionStatus { resolved, missing, ambiguous }

final class BookmarkResolution {
  const BookmarkResolution._({required this.status, this.track, this.cue});

  const BookmarkResolution.resolved({
    required SubtitleTrack track,
    required SubtitleCue cue,
  }) : this._(
         status: BookmarkResolutionStatus.resolved,
         track: track,
         cue: cue,
       );

  const BookmarkResolution.missing()
    : this._(status: BookmarkResolutionStatus.missing);

  const BookmarkResolution.ambiguous()
    : this._(status: BookmarkResolutionStatus.ambiguous);

  final BookmarkResolutionStatus status;
  final SubtitleTrack? track;
  final SubtitleCue? cue;
}
