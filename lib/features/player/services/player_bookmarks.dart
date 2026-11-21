import 'package:uuid/uuid.dart';

import '../../bookmarks/bookmark_repository.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../../bookmarks/domain/bookmark_resolver.dart';
import '../../library/material_repository.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/domain/subtitle_time.dart';

typedef PlayerBookmarkIndex = Map<(String, int, String), Bookmark>;

final class PlayerBookmarks {
  const PlayerBookmarks(this.repository);

  final BookmarkRepository repository;

  Future<PlayerBookmarkIndex> load(
    String materialId,
    List<SubtitleTrack> tracks,
  ) async {
    final bookmarks = await repository.listBookmarks();
    final index = <(String, int, String), Bookmark>{};
    for (final bookmark in bookmarks) {
      if (bookmark.materialId != materialId) continue;
      final match = const BookmarkResolver().resolve(bookmark, tracks);
      if (match.status == BookmarkResolutionStatus.resolved) {
        index[key(match.track!, match.cue!)] = bookmark;
      }
    }
    return Map.unmodifiable(index);
  }

  Future<Bookmark?> toggle(
    LearningMaterial material,
    SubtitleTrack track,
    SubtitleCue cue,
    Bookmark? resolved,
  ) async {
    final start = subtitleToAudioMs(cue.startMs, track.offsetMs);
    final anchor = BookmarkCueAnchor(
      trackId: track.id,
      trackRevision: track.revision,
      languageTag: track.languageTag,
      cueId: cue.id,
      cueText: cue.text,
      startMs: start < 0 ? 0 : start,
      endMs: subtitleToAudioMs(cue.endMs, track.offsetMs),
    );
    final existing =
        resolved ??
        await repository.findForAnchor(materialId: material.id, anchor: anchor);
    if (existing != null) {
      await repository.removeBookmark(existing.id);
      return null;
    }
    return repository.addBookmark(
      Bookmark(
        id: const Uuid().v4(),
        ownerId: material.ownerId,
        materialId: material.id,
        anchor: anchor,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  static (String, int, String) key(SubtitleTrack track, SubtitleCue cue) =>
      (track.id, track.revision, cue.id);
}
