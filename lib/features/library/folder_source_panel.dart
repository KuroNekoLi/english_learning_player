import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/folder_access_gateway.dart';
import 'folder_source_view_model.dart';

final class FolderSourcePanel extends ConsumerWidget {
  const FolderSourcePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(folderSourceViewModelProvider);
    final viewModel = ref.read(folderSourceViewModelProvider.notifier);
    final connected =
        state.grantStatus == GrantStatus.valid ||
        state.grantStatus == GrantStatus.stale;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.folder_special_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.displayLabel ?? 'iCloud 資料夾來源',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    state.error ??
                        state.reconciliationSummary ??
                        (connected
                            ? '可讀取 ${state.availableCount} 個檔案，'
                                  '${state.pendingCount} 個仍在下載'
                            : '來源唯讀；授權留存在這台 Mac'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (state.isBusy)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              TextButton(
                onPressed: connected ? viewModel.refresh : viewModel.connect,
                child: Text(connected ? '重新掃描' : '選擇資料夾'),
              ),
              if (connected)
                IconButton(
                  tooltip: '解除資料夾授權',
                  onPressed: viewModel.disconnect,
                  icon: const Icon(Icons.link_off),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
