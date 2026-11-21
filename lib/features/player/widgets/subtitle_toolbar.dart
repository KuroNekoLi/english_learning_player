import 'package:flutter/material.dart';

import '../../learning/domain/learning_session.dart';

final class SubtitleToolbar extends StatelessWidget {
  const SubtitleToolbar({
    super.key,
    required this.visibility,
    required this.onVisibilityChanged,
    required this.onSettings,
  });

  final SubtitleVisibility visibility;
  final ValueChanged<SubtitleVisibility>? onVisibilityChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Semantics(
          header: true,
          child: Text('逐句字幕', style: Theme.of(context).textTheme.titleMedium),
        ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<SubtitleVisibility>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: SubtitleVisibility.englishOnly,
                  label: Text('英文'),
                ),
                ButtonSegment(
                  value: SubtitleVisibility.chineseOnly,
                  label: Text('中文'),
                ),
                ButtonSegment(
                  value: SubtitleVisibility.bilingual,
                  label: Text('雙語'),
                ),
              ],
              selected: {
                if (visibility != SubtitleVisibility.hidden) visibility,
              },
              emptySelectionAllowed: true,
              onSelectionChanged: onVisibilityChanged == null
                  ? null
                  : (selection) {
                      if (selection.isNotEmpty) {
                        onVisibilityChanged!(selection.first);
                      }
                    },
            ),
            IconButton(
              tooltip: '字幕設定',
              onPressed: onSettings,
              icon: const Icon(Icons.closed_caption_outlined),
            ),
          ],
        ),
      ],
    ),
  );
}
