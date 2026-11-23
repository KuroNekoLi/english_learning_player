import 'package:material_ui/material_ui.dart';

import '../../progress/domain/progress_models.dart';

Future<bool?> showProgressConflictDialog(
  BuildContext context,
  ProgressCandidate candidate,
) {
  final seconds = candidate.checkpoint.positionMs ~/ 1000;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('選擇續播位置'),
      content: Text('此裝置保留了一筆離線進度，位置為 $seconds 秒。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('保留雲端位置'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('採用離線位置'),
        ),
      ],
    ),
  );
}
