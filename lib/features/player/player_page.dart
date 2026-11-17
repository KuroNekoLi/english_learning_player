import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/learning/domain/learning_session.dart';
import '../../features/library/material_repository.dart';
import '../../features/subtitles/domain/subtitle_models.dart';
import 'player_view_model.dart';

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
          appBar: AppBar(
            title: Text(widget.material.title, maxLines: 1),
            actions: [
              IconButton(
                tooltip: state.isCurrentCueBookmarked ? '移除收藏' : '收藏本句',
                onPressed: state.isReady && state.learning?.currentCue != null
                    ? () => unawaited(viewModel.toggleBookmark())
                    : null,
                icon: Icon(
                  state.isCurrentCueBookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
              ),
              IconButton(
                tooltip: '字幕設定',
                onPressed: state.isReady
                    ? () => _showSubtitleSettings(context, state, viewModel)
                    : null,
                icon: const Icon(Icons.subtitles_outlined),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _MaterialSummary(material: widget.material),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _subtitleContent(state, viewModel)),
                  ],
                );
              }
              return _subtitleContent(state, viewModel);
            },
          ),
          bottomNavigationBar: _PlaybackControls(
            state: state,
            viewModel: viewModel,
          ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _ActiveSubtitleCard(
          state: state,
          onTap: state.learning?.currentCue == null
              ? null
              : () => unawaited(
                  viewModel.playCue(state.learning!.currentCue!.id),
                ),
        ),
      ),
    );
  }

  Future<void> _showSubtitleSettings(
    BuildContext context,
    PlayerViewState state,
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
        child: SubtitleSettingsSheet(
          tracks: state.subtitleTracks,
          onSelect: (track) async {
            await viewModel.selectSubtitleTrack(track);
            if (context.mounted) Navigator.of(context).pop();
          },
          onOffsetChanged: viewModel.setSubtitleOffset,
        ),
      ),
    ),
  );
}

final class _MaterialSummary extends StatelessWidget {
  const _MaterialSummary({required this.material});

  final LearningMaterial material;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.headphones_rounded, size: 32),
        ),
        const SizedBox(height: 20),
        Text(material.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('本機教材 · 可離線播放'),
      ],
    ),
  );
}

final class _ActiveSubtitleCard extends StatelessWidget {
  const _ActiveSubtitleCard({required this.state, this.onTap});

  final PlayerViewState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final learning = state.learning;
    final cue = learning?.currentCue;
    if (learning == null || cue == null) {
      final message = state.englishTrack == null ? '尚未提供英文字幕' : '播放至字幕時會在此顯示';
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final visibility = learning.subtitleVisibility;
    final showEnglish =
        visibility == SubtitleVisibility.bilingual ||
        visibility == SubtitleVisibility.englishOnly;
    final showChinese =
        visibility == SubtitleVisibility.bilingual ||
        visibility == SubtitleVisibility.chineseOnly;

    return Card(
      key: const ValueKey('activeSubtitleCard'),
      margin: const EdgeInsets.all(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('目前句子', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  const Icon(Icons.touch_app_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('點一下重播'),
                ],
              ),
              const SizedBox(height: 24),
              if (visibility == SubtitleVisibility.hidden)
                Text(
                  '字幕已遮蔽',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                )
              else ...[
                if (showEnglish)
                  Semantics(
                    label: '英文字幕',
                    child: Text(
                      cue.text,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                if (showChinese) ...[
                  if (showEnglish) const SizedBox(height: 20),
                  if (learning.translationCues.isEmpty)
                    Text(
                      '未提供翻譯',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  else
                    for (final translation in learning.translationCues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Semantics(
                          label: '中文字幕',
                          child: Text(
                            translation.text,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({required this.state, required this.viewModel});

  final PlayerViewState state;
  final PlayerViewModel viewModel;

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

final class _PlaybackControlsState extends State<_PlaybackControls> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final viewModel = widget.viewModel;
    final playback = state.playback;
    final learning = state.learning;
    final duration = playback?.durationMs;
    final position = playback?.positionMs ?? 0;
    final canSeek = state.isReady && duration != null && duration > 0;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.errorMessage != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  Text(_timeLabel(position)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('playbackPositionSlider'),
                      min: 0,
                      max: (duration ?? 1).toDouble(),
                      value: canSeek
                          ? (_dragPosition ?? position.toDouble()).clamp(
                              0,
                              duration.toDouble(),
                            )
                          : 0,
                      onChanged: canSeek
                          ? (value) => setState(() => _dragPosition = value)
                          : null,
                      onChangeEnd: canSeek
                          ? (value) {
                              setState(() => _dragPosition = null);
                              unawaited(viewModel.seekTo(value.round()));
                            }
                          : null,
                    ),
                  ),
                  Text(duration == null ? '--:--' : _timeLabel(duration)),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 0,
                children: [
                  IconButton(
                    tooltip: '重播本句',
                    onPressed: learning?.currentCue == null
                        ? null
                        : () => unawaited(viewModel.replay()),
                    icon: const Icon(Icons.replay_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: playback?.playing == true ? '暫停' : '播放',
                    onPressed: state.isReady
                        ? () => unawaited(viewModel.togglePlayback())
                        : null,
                    icon: Icon(
                      playback?.playing == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一句',
                    onPressed: learning?.currentCue == null
                        ? null
                        : () => unawaited(viewModel.nextCue()),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    tooltip: playback?.currentLoop == null ? '循環本句' : '取消循環',
                    onPressed: learning?.currentCue == null
                        ? null
                        : () => unawaited(viewModel.toggleCueLoop()),
                    color: playback?.currentLoop == null
                        ? null
                        : Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.repeat_one_rounded),
                  ),
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    initialValue: playback?.speed ?? 1,
                    onSelected: (speed) => unawaited(viewModel.setSpeed(speed)),
                    itemBuilder: (context) => [
                      for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                        PopupMenuItem(value: speed, child: Text('$speed×')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${playback?.speed ?? 1}×'),
                    ),
                  ),
                  if (learning?.mode != LearningMode.intensive)
                    PopupMenuButton<SubtitleVisibility>(
                      tooltip: '字幕顯示方式',
                      onSelected: viewModel.setNormalVisibility,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: SubtitleVisibility.bilingual,
                          child: Text('雙語'),
                        ),
                        PopupMenuItem(
                          value: SubtitleVisibility.englishOnly,
                          child: Text('只顯示英文'),
                        ),
                        PopupMenuItem(
                          value: SubtitleVisibility.chineseOnly,
                          child: Text('只顯示中文'),
                        ),
                        PopupMenuItem(
                          value: SubtitleVisibility.hidden,
                          child: Text('隱藏字幕'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.closed_caption_outlined),
                      ),
                    ),
                  _learningAction(learning, viewModel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _learningAction(
    LearningSessionState? learning,
    PlayerViewModel viewModel,
  ) {
    if (learning == null) {
      return const Tooltip(
        message: '需要英文字幕才能使用精聽模式',
        child: Icon(Icons.school_outlined),
      );
    }
    if (learning.mode != LearningMode.intensive) {
      return TextButton.icon(
        onPressed: viewModel.toggleIntensiveMode,
        icon: const Icon(Icons.school_outlined),
        label: const Text('精聽'),
      );
    }
    final label = switch (learning.phase) {
      IntensivePhase.blindListening => '顯示英文',
      IntensivePhase.englishShown => '顯示中文',
      IntensivePhase.bilingualShown => '重新遮蔽',
    };
    return FilledButton.tonal(
      onPressed: viewModel.revealNext,
      child: Text(label),
    );
  }

  String _timeLabel(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }
}

final class SubtitleSettingsSheet extends StatefulWidget {
  const SubtitleSettingsSheet({
    super.key,
    required this.tracks,
    required this.onSelect,
    required this.onOffsetChanged,
  });

  final List<SubtitleTrack> tracks;
  final ValueChanged<SubtitleTrack> onSelect;
  final Future<void> Function(SubtitleTrack track, int offsetMs)
  onOffsetChanged;

  @override
  State<SubtitleSettingsSheet> createState() => _SubtitleSettingsSheetState();
}

final class _SubtitleSettingsSheetState extends State<SubtitleSettingsSheet> {
  final Map<String, int> _offsets = {};

  @override
  Widget build(BuildContext context) {
    final english = _selectedTrack('en');
    final chinese = _selectedTrack('zh');
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('字幕設定', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (widget.tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('尚未匯入字幕'),
              )
            else ...[
              _languageGroup(context, '英文', 'en', english),
              const Divider(),
              _languageGroup(context, '中文', 'zh', chinese),
              if (english != null || chinese != null) ...[
                const Divider(height: 28),
                if (english != null) _offsetControl(context, english),
                if (chinese != null) _offsetControl(context, chinese),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _languageGroup(
    BuildContext context,
    String label,
    String language,
    SubtitleTrack? selected,
  ) {
    final tracks = widget.tracks
        .where((track) => track.languageTag.toLowerCase().startsWith(language))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('沒有可選字幕軌'),
          )
        else
          for (final track in tracks)
            RadioListTile<String>(
              value: track.id,
              groupValue: selected?.id,
              onChanged: (_) => widget.onSelect(track),
              title: Text(track.sourceName),
              subtitle: Text(
                track.selectionMode == SubtitleSelectionMode.manual
                    ? '手動指定'
                    : '自動配對',
              ),
              contentPadding: EdgeInsets.zero,
            ),
      ],
    );
  }

  Widget _offsetControl(BuildContext context, SubtitleTrack track) {
    final value = _offsets[track.id] ?? track.offsetMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${track.languageTag} 偏移：$value ms'),
        Slider(
          min: -2000,
          max: 2000,
          divisions: 80,
          value: value.clamp(-2000, 2000).toDouble(),
          label: '$value ms',
          onChanged: (next) =>
              setState(() => _offsets[track.id] = next.round()),
          onChangeEnd: (next) =>
              unawaited(widget.onOffsetChanged(track, next.round())),
        ),
      ],
    );
  }

  SubtitleTrack? _selectedTrack(String language) {
    for (final track in widget.tracks) {
      if (track.isSelected &&
          track.languageTag.toLowerCase().startsWith(language)) {
        return track;
      }
    }
    return null;
  }
}
