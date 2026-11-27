import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/learning/domain/learning_session.dart';
import '../../features/library/material_repository.dart';
import 'player_view_model.dart';
import 'subtitle_style.dart';
import '../dictionary/dictionary_dependencies.dart';
import 'widgets/subtitle_style_sheet.dart';
import 'widgets/playback_controls.dart';
import 'widgets/subtitle_empty_state.dart';
import 'widgets/subtitle_settings_sheet.dart';
import 'widgets/subtitle_toolbar.dart';
import 'widgets/subtitle_transcript.dart';

export 'widgets/subtitle_settings_sheet.dart';

final class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.material,
    this.initialCueId,
    this.autoplay = false,
  });

  final LearningMaterial material;
  final String? initialCueId;
  final bool autoplay;

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
              .open(
                widget.material,
                initialCueId: widget.initialCueId,
                autoplay: widget.autoplay,
              ),
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
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            viewModel.previousCue,
        const SingleActivator(LogicalKeyboardKey.keyA): viewModel.previousCue,
        const SingleActivator(LogicalKeyboardKey.keyS): viewModel.replay,
        const SingleActivator(LogicalKeyboardKey.keyD): viewModel.nextCue,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Tooltip(
              message: widget.material.title,
              excludeFromSemantics: true,
              child: Text(
                _displayTitle(widget.material.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
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

    final style =
        ref.watch(subtitleStyleProvider).asData?.value ?? const SubtitleStyle();
    final savedWords = style.highlightSavedWords
        ? ref.watch(savedDictionaryWordKeysProvider)
        : const <String>{};
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: style.readingWidth < 900 ? 900 : style.readingWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubtitleToolbar(
                visibility: state.normalVisibility,
                onVisibilityChanged:
                    state.learning?.mode == LearningMode.intensive
                    ? null
                    : viewModel.setNormalVisibility,
                onSettings: () => _showSubtitleSettings(context, viewModel),
              ),
              Expanded(
                child: state.timeline == null
                    ? SubtitleEmptyState(
                        onImport: () =>
                            _showSubtitleSettings(context, viewModel),
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: style.readingWidth,
                          ),
                          child: SubtitleTranscript(
                            key: ValueKey(
                              '${widget.material.id}:${state.englishTrack!.id}:${state.englishTrack!.revision}:${state.subtitleTracks.length}',
                            ),
                            timeline: state.timeline!,
                            style: style,
                            savedWords: savedWords,
                            materialId: widget.material.id,
                            materialTitle: widget.material.title,
                            visibility:
                                state.learning?.subtitleVisibility ??
                                state.normalVisibility,
                            intensive:
                                state.learning?.mode == LearningMode.intensive,
                            activeCueId: state.learning?.currentCue?.id,
                            playing: state.playback?.playing == true,
                            isCurrentCueBookmarked:
                                state.isCurrentCueBookmarked,
                            onPlayCue: viewModel.playCue,
                            onTogglePlayback: viewModel.togglePlayback,
                            onBookmark: viewModel.toggleBookmark,
                          ),
                        ),
                      ),
              ),
              const Divider(height: 1),
              PlaybackControls(state: state, viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }

  String _displayTitle(String title) => title
      .replaceFirst(RegExp(r'\.(m4a|mp3|wav|mp4)$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*\[[A-Za-z0-9_-]{11}\]$'), '')
      .replaceAll('_', ' ')
      .trim();

  Future<void> _showSubtitleStyle(BuildContext context) async {
    final initial =
        ref.read(subtitleStyleProvider).asData?.value ?? const SubtitleStyle();
    final result = await showModalBottomSheet<SubtitleStyle>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SubtitleStyleSheet(initial: initial),
    );
    if (result == null || !mounted) return;
    try {
      await saveSubtitleStyle(result);
      if (mounted) ref.invalidate(subtitleStyleProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(this.context)
            .showSnackBar(const SnackBar(content: Text('無法儲存字幕樣式，請重試。')));
      }
    }
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
              onStyle: () => _showSubtitleStyle(context),
              visibility: settings.visibility,
              onVisibilityChanged: viewModel.setNormalVisibility,
              onImport: () async {
                final source = await viewModel.pickSubtitle();
                if (source == null || !context.mounted) return;
                final imported = await viewModel.importSubtitle(source: source);
                if (!imported) {
                  if (!context.mounted) return;
                  final message = ref
                      .read(playerViewModelProvider)
                      .errorMessage;
                  if (message != null) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(message)));
                  }
                  return;
                }
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
