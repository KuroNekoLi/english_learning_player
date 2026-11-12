import 'domain/bookmark.dart';

abstract interface class BookmarkRepository {
  Future<List<Bookmark>> listBookmarks();

  Future<Bookmark?> findForAnchor({
    required String materialId,
    required BookmarkCueAnchor anchor,
  });

  Future<Bookmark> addBookmark(Bookmark bookmark);

  Future<void> removeBookmark(String bookmarkId);
}
