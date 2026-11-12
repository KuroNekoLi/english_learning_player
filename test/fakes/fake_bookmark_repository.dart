import 'package:english_learning_player/features/bookmarks/bookmark_repository.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark.dart';

final class FakeBookmarkRepository implements BookmarkRepository {
  final Map<String, Bookmark> _items = {};

  @override
  Future<List<Bookmark>> listBookmarks() async =>
      List.unmodifiable(_items.values.where((bookmark) => !bookmark.isDeleted));

  @override
  Future<Bookmark?> findForAnchor({
    required String materialId,
    required BookmarkCueAnchor anchor,
  }) async {
    for (final bookmark in _items.values) {
      if (!bookmark.isDeleted &&
          bookmark.materialId == materialId &&
          bookmark.anchor.trackId == anchor.trackId &&
          bookmark.anchor.trackRevision == anchor.trackRevision &&
          bookmark.anchor.cueId == anchor.cueId) {
        return bookmark;
      }
    }
    return null;
  }

  @override
  Future<Bookmark> addBookmark(Bookmark bookmark) async {
    final existing = await findForAnchor(
      materialId: bookmark.materialId,
      anchor: bookmark.anchor,
    );
    if (existing != null) return existing;
    _items[bookmark.id] = bookmark;
    return bookmark;
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    final bookmark = _items[bookmarkId];
    if (bookmark == null) return;
    _items[bookmarkId] = Bookmark(
      id: bookmark.id,
      ownerId: bookmark.ownerId,
      materialId: bookmark.materialId,
      anchor: bookmark.anchor,
      createdAt: bookmark.createdAt,
      deletedAt: DateTime.utc(2026),
    );
  }
}
