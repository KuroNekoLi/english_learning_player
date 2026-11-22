import 'package:flutter/material.dart';

enum LibraryItemAction {
  multiSelect,
  rename,
  move,
  importSubtitles,
  generateSubtitles,
  delete,
  information,
}

final class LibraryItemMenu extends StatelessWidget {
  const LibraryItemMenu({
    super.key,
    required this.onSelected,
    this.availableActions = const {
      LibraryItemAction.multiSelect,
      LibraryItemAction.rename,
      LibraryItemAction.move,
      LibraryItemAction.delete,
      LibraryItemAction.importSubtitles,
      LibraryItemAction.information,
    },
    this.folder = false,
  });

  final ValueChanged<LibraryItemAction> onSelected;
  final Set<LibraryItemAction> availableActions;
  final bool folder;

  static const _items = <(LibraryItemAction, IconData, String)>[
    (LibraryItemAction.multiSelect, Icons.checklist, '多選'),
    (LibraryItemAction.rename, Icons.edit_outlined, '重新命名'),
    (LibraryItemAction.move, Icons.drive_file_move_outlined, '移動'),
    (LibraryItemAction.importSubtitles, Icons.subtitles_outlined, '匯入字幕'),
    (LibraryItemAction.generateSubtitles, Icons.auto_awesome, '產生字幕'),
    (LibraryItemAction.delete, Icons.delete_outline, '刪除'),
    (LibraryItemAction.information, Icons.info_outline, '資訊'),
  ];

  @override
  Widget build(BuildContext context) => PopupMenuButton<LibraryItemAction>(
    tooltip: '更多選項',
    icon: const Icon(Icons.more_vert),
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final (action, icon, label) in _items)
        if (!folder ||
            const {
              LibraryItemAction.rename,
              LibraryItemAction.move,
              LibraryItemAction.delete,
              LibraryItemAction.information,
            }.contains(action))
          PopupMenuItem<LibraryItemAction>(
            value: action,
            enabled: availableActions.contains(action),
            labelTextStyle: action == LibraryItemAction.delete
                ? WidgetStateProperty.resolveWith(
                    (states) =>
                        Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: states.contains(WidgetState.disabled)
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.error,
                        ),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  icon,
                  color:
                      action == LibraryItemAction.delete &&
                          availableActions.contains(action)
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: 16),
                Text(label),
              ],
            ),
          ),
    ],
  );
}
