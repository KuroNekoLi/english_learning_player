import 'package:material_ui/material_ui.dart';

import '../../../core/design_system/editorial_components.dart';

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
            EditorialLanguageControl<SubtitleVisibility>(
              options: const {
                SubtitleVisibility.englishOnly: '英文',
                SubtitleVisibility.chineseOnly: '中文',
                SubtitleVisibility.bilingual: '雙語',
              },
              selected: visibility,
              onChanged: onVisibilityChanged,
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
