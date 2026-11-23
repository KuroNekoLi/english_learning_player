import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subtitles/services/subtitle_import_service.dart';
import '../library_folder_view_model.dart';
import '../library_view_model.dart';
import 'library_add_menu.dart';
import 'library_material_picker.dart';

final class LibraryActionsMenu extends ConsumerStatefulWidget {
  const LibraryActionsMenu({
    super.key,
    required this.onImportMedia,
    this.onImportFolder,
  });

  final VoidCallback? onImportMedia;
  final VoidCallback? onImportFolder;

  @override
  ConsumerState<LibraryActionsMenu> createState() => _LibraryActionsMenuState();
}

final class _LibraryActionsMenuState extends ConsumerState<LibraryActionsMenu> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryViewModelProvider);
    return LibraryAddMenu(
      onImportMedia: _busy ? null : widget.onImportMedia,
      onImportFolder: widget.onImportFolder,
      onImportSubtitle: _busy || !library.hasValue ? null : _importSubtitle,
      onCreateFolder: _busy ? null : _createFolder,
    );
  }

  Future<void> _importSubtitle() async {
    setState(() => _busy = true);
    try {
      final material = await pickLibraryMaterial(
        context,
        title: '選擇要加入字幕的教材',
        materials: ref.read(libraryViewModelProvider).value ?? const [],
        emptyMessage: '請先匯入或下載教材，再為它加入 SRT 字幕。',
      );
      if (material == null || !mounted) return;
      final count = await ref.read(librarySubtitleImportProvider)(material);
      if (count != null) _showMessage('「${material.title}」已匯入 $count 條字幕軌。');
    } on SubtitleLanguageDetectionException {
      _showMessage('無法辨識字幕語言，請檢查 SRT 內容或檔名。');
    } catch (_) {
      _showMessage('字幕匯入失敗，請確認檔案是有效的 UTF-8 SRT。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFolder() async {
    setState(() => _busy = true);
    try {
      final name = await _requestFolderName(context);
      if (name == null || !mounted) return;
      await ref.read(libraryFoldersProvider.notifier).create(name);
      _showMessage('已新增資料夾「$name」。');
    } catch (_) {
      _showMessage('無法新增資料夾，請稍後重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

Future<String?> _requestFolderName(BuildContext context) {
  var name = '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('新增資料夾'),
        content: TextField(
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '資料夾名稱'),
          onChanged: (value) => setState(() => name = value.trim()),
          onSubmitted: (_) {
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: name.isEmpty
                ? null
                : () => Navigator.of(context).pop(name),
            child: const Text('建立'),
          ),
        ],
      ),
    ),
  );
}
