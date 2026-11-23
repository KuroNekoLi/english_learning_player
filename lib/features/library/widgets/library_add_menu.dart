import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

final class LibraryAddMenu extends StatelessWidget {
  const LibraryAddMenu({
    super.key,
    required this.onImportMedia,
    required this.onImportSubtitle,
    required this.onCreateFolder,
    this.onImportFolder,
  });

  final VoidCallback? onImportMedia;
  final VoidCallback? onImportSubtitle;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onImportFolder;

  bool get _showPhotoImport =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.download_outlined),
        onPressed: onImportMedia,
        child: const Text('匯入媒體'),
      ),
      if (_showPhotoImport)
        const MenuItemButton(
          leadingIcon: Icon(Icons.photo_library_outlined),
          onPressed: null,
          child: Text('從相簿匯入（尚未提供）'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
        onPressed: onImportFolder,
        child: Text(onImportFolder == null ? '匯入資料夾（此平台尚未提供）' : '匯入資料夾'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.subtitles_outlined),
        onPressed: onImportSubtitle,
        child: const Text('匯入字幕'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.create_new_folder_outlined),
        onPressed: onCreateFolder,
        child: const Text('新增資料夾'),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      tooltip: '新增',
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.add),
    ),
  );
}
