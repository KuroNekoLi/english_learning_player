import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync_preference.dart';

final class SyncConsentControls extends ConsumerWidget {
  const SyncConsentControls({
    super.key,
    required this.preferenceKey,
    required this.busy,
    required this.onSync,
    this.readOnly = false,
  });

  final SyncPreferenceKey preferenceKey;
  final bool busy;
  final Future<void> Function() onSync;
  final bool readOnly;

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
          Text(
            readOnly ? '開啟教材下載？' : '開啟教材同步？',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            readOnly
                ? '此帳號密碼登入只能讀取雲端教材。開啟後會自動下載此 Google 帳號的音檔與字幕，不會上傳或修改雲端資料。'
                : '開啟後，這個帳號匯入的音檔與字幕會自動上傳到 Firebase。其他裝置用同一帳號登入並開啟同步後，就能下載。',
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: busy ? null : () => choose(SyncPreference.enabled),
                child: Text(readOnly ? '開啟自動下載' : '開啟同步'),
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
          title: Text(readOnly ? '自動下載音檔與字幕' : '自動同步音檔與字幕'),
          value: enabled,
          onChanged: (on) =>
              choose(on ? SyncPreference.enabled : SyncPreference.disabled),
        ),
        FilledButton(
          onPressed: busy || !enabled ? null : onSync,
          child: Text(readOnly ? '立即更新與下載' : '立即同步'),
        ),
      ],
    );
  }
}
