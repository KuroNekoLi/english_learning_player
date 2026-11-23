import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync_preference.dart';

final class SyncConsentControls extends ConsumerWidget {
  const SyncConsentControls({
    super.key,
    required this.preferenceKey,
    required this.busy,
    required this.onSync,
  });

  final SyncPreferenceKey preferenceKey;
  final bool busy;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = syncPreferenceProvider(preferenceKey);
    final preference = ref.watch(provider);
    final choice = preference.asData?.value;
    final choose = ref.read(provider.notifier).choose;
    if (preference.isLoading) return const LinearProgressIndicator();
    if (preference.hasError) {
      return ListTile(
        title: const Text('無法讀取或儲存同步設定。'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(provider),
          child: const Text('重試'),
        ),
      );
    }
    if (choice == SyncPreference.undecided) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('開啟教材同步？', style: Theme.of(context).textTheme.titleLarge),
          const Text('開啟後，這個帳號匯入的音檔與字幕會自動上傳到 Firebase。其他裝置用同一帳號登入並開啟同步後，就能下載。'),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: busy ? null : () => choose(SyncPreference.enabled),
                child: const Text('開啟同步'),
              ),
              TextButton(
                onPressed: busy ? null : () => choose(SyncPreference.disabled),
                child: const Text('稍後'),
              ),
            ],
          ),
        ],
      );
    }
    final enabled = choice == SyncPreference.enabled;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('自動同步音檔與字幕'),
          value: enabled,
          onChanged: (on) =>
              choose(on ? SyncPreference.enabled : SyncPreference.disabled),
        ),
        FilledButton(
          onPressed: busy || !enabled ? null : onSync,
          child: const Text('立即同步'),
        ),
      ],
    );
  }
}
