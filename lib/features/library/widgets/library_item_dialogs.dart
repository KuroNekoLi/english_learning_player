import 'package:material_ui/material_ui.dart';

import '../library_folder_repository.dart';

Future<({String? id})?> pickLibraryDestination(
  BuildContext context,
  List<LibraryFolder> folders,
  String? movingFolder,
  String? current,
) {
  final byId = {for (final folder in folders) folder.id: folder};
  final options = <({String label, String? id})>[
    if (current != null) (label: '教材庫首頁', id: null),
  ];
  for (final folder in folders) {
    if (folder.id == current) continue;
    final path = <String>[];
    var ancestor = folder;
    var allowed = true;
    while (true) {
      if (ancestor.id == movingFolder) {
        allowed = false;
        break;
      }
      path.add(ancestor.title);
      final parent = byId[ancestor.parentId];
      if (parent == null) break;
      ancestor = parent;
    }
    if (allowed) options.add((label: path.reversed.join(' / '), id: folder.id));
  }
  return showDialog<({String? id})>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('移動到'),
      children: [
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('目前沒有可用的目的地。'),
          ),
        for (final option in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (id: option.id)),
            child: Text(option.label),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

final class RenameLibraryItemDialog extends StatefulWidget {
  const RenameLibraryItemDialog(this.title, {super.key});
  final String title;

  @override
  State<RenameLibraryItemDialog> createState() => _RenameItemDialogState();
}

final class _RenameItemDialogState extends State<RenameLibraryItemDialog> {
  late final controller = TextEditingController(text: widget.title);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = controller.text.trim();
    final canSave =
        name.isNotEmpty && name.runes.length <= 80 && name != widget.title;
    void save() => Navigator.pop(context, name);
    return AlertDialog(
      title: const Text('重新命名'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '名稱'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (canSave) save();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: canSave ? save : null, child: const Text('儲存')),
      ],
    );
  }
}
