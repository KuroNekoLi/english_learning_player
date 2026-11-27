import 'package:material_ui/material_ui.dart';

import 'editorial_tokens.dart';

/// A flat row for reading lists. Keeps the child's original interaction semantics.
final class EditorialListRow extends StatelessWidget {
  const EditorialListRow({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [child, const Divider()],
    ),
  );
}

final class EditorialLanguageControl<T> extends StatelessWidget {
  const EditorialLanguageControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Wrap(
      spacing: 4,
      children: [
        for (final entry in options.entries)
          Semantics(
            selected: entry.key == selected,
            child: TextButton(
              onPressed: onChanged == null ? null : () => onChanged!(entry.key),
              style: TextButton.styleFrom(
                foregroundColor: entry.key == selected
                    ? c.primary
                    : c.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.value),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 2,
                    color: entry.key == selected
                        ? c.primary
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A compact editorial heading shared across collection screens.
final class EditorialPageHeading extends StatelessWidget {
  const EditorialPageHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });
  final String eyebrow, title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow,
            style: t.labelSmall?.copyWith(
              color: c.primary,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(header: true, child: Text(title, style: t.headlineMedium)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}
