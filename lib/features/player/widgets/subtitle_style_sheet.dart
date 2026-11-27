import 'package:material_ui/material_ui.dart';

import '../../../core/design_system/editorial_tokens.dart';
import '../../../core/design_system/editorial_typography.dart';

import '../subtitle_style.dart';

final class SubtitleStyleSheet extends StatefulWidget {
  const SubtitleStyleSheet({super.key, required this.initial});
  final SubtitleStyle initial;

  @override
  State<SubtitleStyleSheet> createState() => _SubtitleStyleSheetState();
}

final class _SubtitleStyleSheetState extends State<SubtitleStyleSheet> {
  late SubtitleStyle _style = widget.initial;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editorial = EditorialColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .83,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '字幕樣式',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _style = const SubtitleStyle()),
                    child: const Text('恢復預設'),
                  ),
                ],
              ),
              const Text(
                '預覽（閱讀寬度按比例顯示）',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: _style.readingWidth / 1200,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: _style.spacing / 2,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: editorial.activeSubtitle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: EditorialTypography.english(
                              context,
                              size: _style.englishSize,
                              height: _style.lineHeight,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Learning a language takes ',
                              ),
                              TextSpan(
                                text: 'practice',
                                style: _style.highlightSavedWords
                                    ? TextStyle(
                                        backgroundColor:
                                            colors.tertiaryContainer,
                                        color: colors.onTertiaryContainer,
                                      )
                                    : null,
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '學習一門語言需要練習。',
                          style: EditorialTypography.translation(
                            context,
                            size: _style.chineseSize,
                            height: _style.lineHeight,
                            color: readableTranslation(
                              editorial.textSecondary,
                              editorial.activeSubtitle,
                              _style.translationOpacity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _slider(
                '英文字體',
                _style.englishSize,
                14,
                32,
                18,
                '${_style.englishSize.round()} px',
                (v) => _style.copyWith(englishSize: v),
              ),
              _slider(
                '中文字體',
                _style.chineseSize,
                12,
                26,
                14,
                '${_style.chineseSize.round()} px',
                (v) => _style.copyWith(chineseSize: v),
              ),
              _slider(
                '行高',
                _style.lineHeight,
                1.2,
                2,
                16,
                _style.lineHeight.toStringAsFixed(2),
                (v) => _style.copyWith(lineHeight: v),
              ),
              _slider(
                '字幕間距',
                _style.spacing,
                4,
                32,
                14,
                '${_style.spacing.round()} px',
                (v) => _style.copyWith(spacing: v),
              ),
              _slider(
                '翻譯不透明度',
                _style.translationOpacity,
                .5,
                1,
                10,
                '${(_style.translationOpacity * 100).round()}%',
                (v) => _style.copyWith(translationOpacity: v),
              ),
              _slider(
                '最大閱讀寬度',
                _style.readingWidth,
                480,
                1200,
                24,
                '${_style.readingWidth.round()} px',
                (v) => _style.copyWith(readingWidth: v),
              ),
              const Text('閱讀寬度在較大的視窗中生效。翻譯顏色會依可讀性調整。'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('高亮已收藏單字'),
                value: _style.highlightSavedWords,
                onChanged: (v) => setState(
                  () => _style = _style.copyWith(highlightSavedWords: v),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_style),
                child: const Text('儲存字幕樣式'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    int divisions,
    String label,
    SubtitleStyle Function(double) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$name · $label'),
      Slider(
        key: ValueKey(name),
        min: min,
        max: max,
        divisions: divisions,
        value: value,
        label: label,
        onChanged: (v) => setState(() => _style = change(v)),
      ),
    ],
  );
}
