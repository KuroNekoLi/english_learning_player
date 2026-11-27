import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_preference.dart';

final class ThemeModeTile extends ConsumerWidget {
  const ThemeModeTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themePreferenceProvider);
    final mode = selected.asData?.value ?? ThemeMode.system;
    String label(ThemeMode value) => switch (value) {
      ThemeMode.system => '跟隨系統',
      ThemeMode.light => '明亮',
      ThemeMode.dark => '深色',
    };
    return ListTile(
      leading: const Icon(Icons.contrast_outlined),
      title: const Text('外觀'),
      subtitle: Text(label(mode)),
      trailing: PopupMenuButton<ThemeMode>(
        tooltip: '切換外觀',
        initialValue: mode,
        enabled: !selected.isLoading,
        onSelected: (value) async {
          try {
            await ref.read(themePreferenceProvider.notifier).select(value);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('無法儲存外觀設定')));
            }
          }
        },
        itemBuilder: (_) => [
          for (final value in ThemeMode.values)
            PopupMenuItem(value: value, child: Text(label(value))),
        ],
        icon: const Icon(Icons.expand_more),
      ),
    );
  }
}
