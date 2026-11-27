import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/material_repository.dart';
import '../player_page.dart';
import '../player_view_model.dart';
import '../recent_playback_provider.dart';

/// Persistent home control for the latest locally resumed material.
final class RecentPlaybackMiniPlayer extends ConsumerWidget {
  const RecentPlaybackMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerViewModelProvider);
    final recent = ref.watch(recentPlaybackProvider).asData?.value;
    final activeMaterial = player.isReady ? player.material : null;
    final material = activeMaterial ?? recent?.material;
    if (material == null) return const SizedBox.shrink();

    final active = activeMaterial?.id == material.id;
    final positionMs = active
        ? player.playback?.positionMs ?? recent?.positionMs ?? 0
        : recent?.positionMs ?? 0;
    final durationMs = active
        ? player.playback?.durationMs
        : material.durationMs;
    final playing = active && player.playback?.playing == true;
    final progress = durationMs != null && durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => _open(context, material),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress != null)
                  LinearProgressIndicator(value: progress, minHeight: 2),
                Row(
                  children: [
                    Icon(
                      Icons.headphones,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            material.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '繼續播放 · ${_time(positionMs)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: playing ? '暫停' : '播放',
                      onPressed: () {
                        if (active) {
                          ref
                              .read(playerViewModelProvider.notifier)
                              .togglePlayback();
                        } else {
                          _open(context, material, autoplay: true);
                        }
                      },
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(
    BuildContext context,
    LearningMaterial material, {
    bool autoplay = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(material: material, autoplay: autoplay),
      ),
    );
  }

  String _time(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
