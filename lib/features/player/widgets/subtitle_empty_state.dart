import 'package:flutter/material.dart';

final class SubtitleEmptyState extends StatelessWidget {
  const SubtitleEmptyState({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.subtitles_off_outlined, size: 40),
        const SizedBox(height: 12),
        const Text('尚未載入字幕'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onImport,
          icon: const Icon(Icons.playlist_add),
          label: const Text('匯入 SRT 字幕'),
        ),
      ],
    ),
  );
}
