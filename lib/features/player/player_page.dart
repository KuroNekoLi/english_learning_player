import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/learning/domain/learning_session.dart';
import '../../features/library/material_repository.dart';
import '../../features/subtitles/domain/subtitle_aligner.dart';
import '../../features/subtitles/domain/bilingual_subtitle_splitter.dart';
import '../../features/subtitles/domain/subtitle_models.dart';
import '../../features/subtitles/services/subtitle_file_picker.dart';
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
  SubtitleVisibility _transcriptVisibility = SubtitleVisibility.bilingual;
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
          _PlayerTransportCard(
            state: state,
            viewModel: viewModel,
            onSubtitleSettings: () =>
                _showSubtitleSettings(context, state, viewModel),
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
                  selected: {_transcriptVisibility},
                  onSelectionChanged: (selection) =>
                      setState(() => _transcriptVisibility = selection.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.englishTrack == null
                ? _SubtitleEmptyState(
                    onImport: () =>
                        _showSubtitleSettings(context, state, viewModel),
                  )
                : _SubtitleTranscript(
                    key: ValueKey(
                      '${state.englishTrack!.id}:${state.englishTrack!.revision}:${state.subtitleTracks.length}',
                    ),
                    state: state,
                    visibility: _transcriptVisibility,
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
          visibility: viewModel.normalVisibility,
          onVisibilityChanged: (visibility) {
            viewModel.setNormalVisibility(visibility);
            if (visibility != SubtitleVisibility.hidden && mounted) {
              setState(() => _transcriptVisibility = visibility);
            }
          },
          onImport: () async {
            final source = await SubtitleFilePicker().pickSubtitle();
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
            final bytes = await source
                .openRead()
                .expand((chunk) => chunk)
                .toList();
            await viewModel.importSubtitle(
              languageTag: language,
              sourceName: source.name,
              bytes: bytes,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
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

final class _SubtitleEmptyState extends StatelessWidget {
  const _SubtitleEmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.subtitles_off_outlined, size: 40),
        const SizedBox(height: 12),
        const Text('尚未載入字幕'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onImport,
          icon: const Icon(Icons.playlist_add),
          label: const Text('匯入 SRT 字幕'),
        ),
      ],
    ),
  );
}

final class _PlayerTransportCard extends StatefulWidget {
  const _PlayerTransportCard({
    required this.state,
    required this.viewModel,
    required this.onSubtitleSettings,
  });

  final PlayerViewState state;
  final PlayerViewModel viewModel;
  final VoidCallback onSubtitleSettings;

  @override
  State<_PlayerTransportCard> createState() => _PlayerTransportCardState();
}

final class _PlayerTransportCardState extends State<_PlayerTransportCard> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final viewModel = widget.viewModel;
    final playback = state.playback;
    final duration = playback?.durationMs;
    final position = playback?.positionMs ?? 0;
    final canSeek = state.isReady && duration != null && duration > 0;
    final learning = state.learning;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Card(
          margin: const EdgeInsets.fromLTRB(18, 16, 18, 4),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 34),
                const SizedBox(height: 8),
                Text(
                  state.material?.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_timeLabel(position)} / ${duration == null ? '--:--' : _timeLabel(duration)}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: '上一句',
                      onPressed: state.englishTrack == null
                          ? null
                          : () => unawaited(viewModel.previousCue()),
                      icon: const Icon(Icons.skip_previous_rounded),
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
                      onPressed: state.englishTrack == null
                          ? null
                          : () => unawaited(viewModel.nextCue()),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    PopupMenuButton<double>(
                      tooltip: '播放速度',
                      initialValue: playback?.speed ?? 1,
                      onSelected: (speed) =>
                          unawaited(viewModel.setSpeed(speed)),
                      itemBuilder: (context) => [
                        for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                          PopupMenuItem(value: speed, child: Text('$speed×')),
                      ],
                      child: Chip(label: Text('${playback?.speed ?? 1}×')),
                    ),
                    ActionChip(
                      label: const Text('單句循環'),
                      avatar: const Icon(Icons.repeat_one_rounded, size: 18),
                      onPressed: learning?.currentCue == null
                          ? null
                          : () => unawaited(viewModel.toggleCueLoop()),
                    ),
                    const Tooltip(
                      message: 'AB 循環尚未提供',
                      child: Chip(
                        avatar: Icon(Icons.repeat_rounded, size: 18),
                        label: Text('AB 循環'),
                      ),
                    ),
                    if (learning != null &&
                        learning.mode != LearningMode.intensive)
                      ActionChip(
                        avatar: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('精聽'),
                        onPressed: viewModel.toggleIntensiveMode,
                      )
                    else if (learning?.mode == LearningMode.intensive)
                      ActionChip(
                        label: Text(switch (learning!.phase) {
                          IntensivePhase.blindListening => '顯示英文',
                          IntensivePhase.englishShown => '顯示中文',
                          IntensivePhase.bilingualShown => '重新遮蔽',
                        }),
                        onPressed: viewModel.revealNext,
                      ),
                    IconButton(
                      tooltip: '字幕設定',
                      onPressed: state.isReady
                          ? widget.onSubtitleSettings
                          : null,
                      icon: const Icon(Icons.closed_caption_outlined),
                    ),
                  ],
                ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SubtitleTranscript extends StatefulWidget {
  const _SubtitleTranscript({
    super.key,
    required this.state,
    required this.visibility,
    required this.onPlayCue,
    required this.onBookmark,
    required this.onRepeatCue,
    required this.onNextCue,
  });

  final PlayerViewState state;
  final SubtitleVisibility visibility;
  final Future<void> Function(String cueId) onPlayCue;
  final Future<void> Function() onBookmark;
  final Future<void> Function() onRepeatCue;
  final Future<void> Function() onNextCue;

  @override
  State<_SubtitleTranscript> createState() => _SubtitleTranscriptState();
}

final class _SubtitleTranscriptState extends State<_SubtitleTranscript> {
  String? _alignmentKey;
  Map<String, List<SubtitleCue>> _translations = const {};

  @override
  void didUpdateWidget(covariant _SubtitleTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureAlignment();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAlignment();
    final english = widget.state.englishTrack!;
    final cues = english.cues.toList()
      ..sort((a, b) {
        final byStart = a.startMs.compareTo(b.startMs);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    return ListView.builder(
      key: const ValueKey('subtitleTranscriptList'),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      itemCount: cues.length,
      itemBuilder: (context, index) {
        final cue = cues[index];
        final active = widget.state.learning?.currentCue?.id == cue.id;
        final translations = _translations[cue.id] ?? const <SubtitleCue>[];
        final inlinePair = const BilingualSubtitleSplitter().split([cue]);
        final englishText = inlinePair?.english.single.text ?? cue.text;
        final inlineChinese = inlinePair?.chinese.single.text;
        final showEnglish =
            widget.visibility == SubtitleVisibility.bilingual ||
            widget.visibility == SubtitleVisibility.englishOnly;
        final showChinese =
            widget.visibility == SubtitleVisibility.bilingual ||
            widget.visibility == SubtitleVisibility.chineseOnly;
        final intensive = widget.state.learning?.mode == LearningMode.intensive;
        final visibility = widget.state.learning?.subtitleVisibility;
        final conceal =
            intensive && (!active || visibility == SubtitleVisibility.hidden);
        return Card(
          key: ValueKey(
            active ? 'activeSubtitleCard' : 'subtitleRow-${cue.id}',
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: active
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Theme.of(context).colorScheme.surface,
          child: InkWell(
            onTap: () => unawaited(widget.onPlayCue(cue.id)),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          active
                              ? '正在播放 · ${_timeRange(cue, english.offsetMs)}'
                              : _timeRange(cue, english.offsetMs),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      if (active)
                        IconButton(
                          tooltip: widget.state.isCurrentCueBookmarked
                              ? '移除收藏'
                              : '收藏本句',
                          onPressed: () => unawaited(widget.onBookmark()),
                          icon: Icon(
                            widget.state.isCurrentCueBookmarked
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                        ),
                    ],
                  ),
                  if (conceal)
                    const Text('字幕已遮蔽')
                  else ...[
                    if (showEnglish)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          englishText,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                    if (showChinese && inlineChinese != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          inlineChinese,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: active
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    else if (showChinese)
                      if (translations.isEmpty)
                        if (widget.state.subtitleTracks.any(
                          (track) =>
                              track.languageTag.toLowerCase().startsWith(
                                'zh',
                              ) &&
                              track.isSelected,
                        ))
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('未找到對應中文字幕'),
                          )
                        else
                          const SizedBox.shrink()
                      else
                        for (final translation in translations)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              translation.text,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: active
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                  ],
                  if (active)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '重播本句',
                            onPressed: () => unawaited(widget.onRepeatCue()),
                            icon: const Icon(Icons.replay_rounded),
                          ),
                          IconButton(
                            tooltip: '下一句',
                            onPressed: () => unawaited(widget.onNextCue()),
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _ensureAlignment() {
    final english = widget.state.englishTrack;
    if (english == null) return;
    final chinese = widget.state.subtitleTracks
        .where(
          (track) =>
              track.isSelected &&
              track.languageTag.toLowerCase().startsWith('zh'),
        )
        .firstOrNull;
    final key =
        '${english.id}:${english.revision}:${english.offsetMs}:${chinese?.id}:${chinese?.revision}:${chinese?.offsetMs}';
    if (key == _alignmentKey) return;
    _alignmentKey = key;
    if (chinese == null) {
      _translations = const {};
      return;
    }
    final alignments = const SubtitleAligner().align(
      sourceCues: english.cues,
      targetCues: chinese.cues,
      sourceOffsetMs: english.offsetMs,
      targetOffsetMs: chinese.offsetMs,
    );
    final chineseById = {for (final cue in chinese.cues) cue.id: cue};
    _translations = {
      for (final item in alignments)
        item.sourceCueId: List.unmodifiable(
          item.targetCueIds
              .map((id) => chineseById[id])
              .whereType<SubtitleCue>(),
        ),
    };
  }

  String _timeRange(SubtitleCue cue, int offsetMs) =>
      '${_timeLabel((cue.startMs + offsetMs).clamp(0, 0x7fffffffffffffff))} – '
      '${_timeLabel((cue.endMs + offsetMs).clamp(0, 0x7fffffffffffffff))}';
}

String _timeLabel(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

final class SubtitleSettingsSheet extends StatefulWidget {
  const SubtitleSettingsSheet({
    super.key,
    required this.tracks,
    required this.onSelect,
    required this.onOffsetChanged,
    required this.onImport,
    required this.visibility,
    required this.onVisibilityChanged,
  });

  final List<SubtitleTrack> tracks;
  final ValueChanged<SubtitleTrack> onSelect;
  final Future<void> Function(SubtitleTrack track, int offsetMs)
  onOffsetChanged;
  final Future<void> Function() onImport;
  final SubtitleVisibility visibility;
  final ValueChanged<SubtitleVisibility> onVisibilityChanged;

  @override
  State<SubtitleSettingsSheet> createState() => _SubtitleSettingsSheetState();
}

final class _SubtitleSettingsSheetState extends State<SubtitleSettingsSheet> {
  final Map<String, int> _offsets = {};
  late SubtitleVisibility _visibility = widget.visibility;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字幕設定',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'AI 語音辨識（尚未提供）',
                  onPressed: null,
                  icon: const Icon(Icons.auto_awesome),
                ),
                IconButton(
                  tooltip: '手動匯入 SRT',
                  onPressed: () => unawaited(widget.onImport()),
                  icon: const Icon(Icons.playlist_add),
                ),
                IconButton(
                  tooltip: '字幕樣式（尚未提供）',
                  onPressed: null,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  (SubtitleVisibility.bilingual, '雙語'),
                  (SubtitleVisibility.englishOnly, '只顯示英文'),
                  (SubtitleVisibility.chineseOnly, '只顯示中文'),
                  (SubtitleVisibility.hidden, '隱藏'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _visibility == option.$1,
                    onSelected: (_) {
                      setState(() => _visibility = option.$1);
                      widget.onVisibilityChanged(option.$1);
                    },
                  ),
              ],
            ),
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
