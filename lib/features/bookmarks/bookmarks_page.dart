import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_page.dart';
import 'bookmark_list_view_model.dart';
import 'domain/bookmark.dart';

final class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(bookmarkListViewModelProvider);
    final viewModel = ref.read(bookmarkListViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: viewModel.refresh,
            child: const Text('無法讀取收藏，重試'),
          ),
        ),
        data: (bookmarks) => bookmarks.isEmpty
            ? const Center(child: Text('目前沒有收藏句子'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: bookmarks.length,
                itemBuilder: (context, index) => _BookmarkTile(
                  item: bookmarks[index],
                  onRemove: () =>
                      unawaited(viewModel.remove(bookmarks[index].bookmark.id)),
                ),
              ),
      ),
    );
  }
}

final class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({required this.item, required this.onRemove});

  final BookmarkListItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bookmark = item.bookmark;
    final resolution = item.resolution;
    final canPlay =
        item.material != null &&
        resolution.status == BookmarkResolutionStatus.resolved;
    final statusLabel = switch (resolution.status) {
      BookmarkResolutionStatus.resolved => item.material?.title ?? '教材不存在',
      BookmarkResolutionStatus.missing => '字幕已更新，暫時無法定位',
      BookmarkResolutionStatus.ambiguous => '字幕有多個可能句子，無法安全定位',
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: canPlay,
        onTap: canPlay
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(
                    material: item.material!,
                    initialCueId: resolution.cue!.id,
                  ),
                ),
              )
            : null,
        title: Text(resolution.cue?.text ?? bookmark.anchor.cueText),
        subtitle: Text(statusLabel),
        isThreeLine: false,
        trailing: IconButton(
          tooltip: '移除收藏',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}
