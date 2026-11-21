import 'package:flutter/material.dart';

import '../../bookmarks/bookmarks_page.dart';
import '../../sync/firebase_sync_panel.dart';
import '../folder_source_panel.dart';

final class SourceManagementPage extends StatelessWidget {
  const SourceManagementPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定與來源管理')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const FolderSourcePanel(),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('帳號與同步'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FirebaseSyncPanel()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('我的收藏'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BookmarksPage()),
          ),
        ),
      ],
    ),
  );
}
