import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/learning/domain/learning_session.dart';
import '../../features/library/material_repository.dart';
import 'player_view_model.dart';
import 'widgets/playback_controls.dart';
import 'widgets/subtitle_empty_state.dart';
import 'widgets/subtitle_settings_sheet.dart';
import 'widgets/subtitle_transcript.dart';

export 'widgets/subtitle_settings_sheet.dart';

final class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.material, this.initialCueId});

  final LearningMaterial material;
  final String? initialCueId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

final class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(playerViewModelProvider.notifier)
              .open(widget.material, initialCueId: widget.initialCueId),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playerViewModelProvider.notifier).onLifecycleExit());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerViewModelProvider);
    final viewModel = ref.read(playerViewModelProvider.notifier);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space):
            viewModel.togglePlayback,
        const SingleActivator(LogicalKeyboardKey.arrowRight): viewModel.nextCue,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.material.title, maxLines: 1)),
          body: _subtitleContent(state, viewModel),
        ),
      ),
    );
  }

  Widget _subtitleContent(PlayerViewState state, PlayerViewModel viewModel) {
    if (state.isLoading || state.status == PlayerLoadStatus.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == PlayerLoadStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(state.errorMessage ?? '無法開啟教材'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => unawaited(viewModel.open(widget.material)),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          PlaybackControls(
            state: state,
            viewModel: viewModel,
            onSubtitleSettings: () => _showSubtitleSettings(context, viewModel),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                Text('逐句雙語字幕', style: Theme.of(context).textTheme.titleLarge),
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
                    if (state.normalVisibility != SubtitleVisibility.hidden)
                      state.normalVisibility,
                  },
                  emptySelectionAllowed: true,
                  onSelectionChanged:
                      state.learning?.mode == LearningMode.intensive
                      ? null
                      : (selection) {
                          if (selection.isNotEmpty) {
                            viewModel.setNormalVisibility(selection.first);
                          }
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: state.timeline == null
                ? SubtitleEmptyState(
                    onImport: () => _showSubtitleSettings(context, viewModel),
                  )
                : SubtitleTranscript(
                    key: ValueKey(
                      '${state.englishTrack!.id}:${state.englishTrack!.revision}:${state.subtitleTracks.length}',
                    ),
                    timeline: state.timeline!,
                    visibility:
                        state.learning?.subtitleVisibility ??
                        state.normalVisibility,
                    intensive: state.learning?.mode == LearningMode.intensive,
                    activeCueId: state.learning?.currentCue?.id,
                    isCurrentCueBookmarked: state.isCurrentCueBookmarked,
                    onPlayCue: viewModel.playCue,
                    onBookmark: viewModel.toggleBookmark,
                    onRepeatCue: viewModel.replay,
                    onNextCue: viewModel.nextCue,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubtitleSettings(
    BuildContext context,
    PlayerViewModel viewModel,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(
              playerViewModelProvider.select(
                (value) => (
                  tracks: value.subtitleTracks,
                  visibility: value.normalVisibility,
                ),
              ),
            );
            return SubtitleSettingsSheet(
              tracks: settings.tracks,
              visibility: settings.visibility,
              onVisibilityChanged: viewModel.setNormalVisibility,
              onImport: () async {
                final source = await viewModel.pickSubtitle();
                if (source == null || !context.mounted) return;
                final language = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('選擇字幕語言'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, 'en'),
                        child: const Text('英文'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, 'zh-TW'),
                        child: const Text('中文'),
                      ),
                    ],
                  ),
                );
                if (language == null || !context.mounted) return;
                final imported = await viewModel.importSubtitle(
                  languageTag: language,
                  source: source,
                );
                if (!imported) return;
                if (context.mounted) Navigator.of(context).pop();
              },
              onSelect: (track) async {
                await viewModel.selectSubtitleTrack(track);
                if (context.mounted) Navigator.of(context).pop();
              },
              onOffsetChanged: viewModel.setSubtitleOffset,
            );
          },
        ),
      ),
    ),
  );
}
