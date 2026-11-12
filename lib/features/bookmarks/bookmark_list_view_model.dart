import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import '../library/material_repository.dart';
import '../subtitles/domain/subtitle_models.dart';
import 'bookmark_dependencies.dart';
import 'domain/bookmark.dart';
import 'domain/bookmark_resolver.dart';

final class BookmarkListItem {
  const BookmarkListItem({
    required this.bookmark,
    required this.material,
    required this.resolution,
  });

  final Bookmark bookmark;
  final LearningMaterial? material;
  final BookmarkResolution resolution;
}

final bookmarkListViewModelProvider =
    AsyncNotifierProvider<BookmarkListViewModel, List<BookmarkListItem>>(
      BookmarkListViewModel.new,
    );

final class BookmarkListViewModel
    extends AsyncNotifier<List<BookmarkListItem>> {
  final BookmarkResolver _resolver = const BookmarkResolver();

  @override
  Future<List<BookmarkListItem>> build() => _loadItems();

  Future<void> remove(String bookmarkId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repository = await ref.read(bookmarkRepositoryProvider.future);
      await repository.removeBookmark(bookmarkId);
      return _loadItems();
    });
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadItems);
  }

  Future<List<BookmarkListItem>> _loadItems() async {
    final bookmarks = await ref.read(bookmarkRepositoryProvider.future);
    final materials = await ref.read(materialRepositoryProvider.future);
    final allBookmarks = await bookmarks.listBookmarks();
    final allMaterials = await materials.listMaterials();
    final materialsById = {
      for (final material in allMaterials) material.id: material,
    };
    final result = <BookmarkListItem>[];
    for (final bookmark in allBookmarks) {
      final material = materialsById[bookmark.materialId];
      final tracks = material == null
          ? const <SubtitleTrack>[]
          : await materials.listSubtitleTracks(material.id);
      result.add(
        BookmarkListItem(
          bookmark: bookmark,
          material: material,
          resolution: _resolver.resolve(bookmark, tracks),
        ),
      );
    }
    return List.unmodifiable(result);
  }
}
