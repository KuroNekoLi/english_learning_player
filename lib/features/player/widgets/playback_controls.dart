import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/design_system/editorial_tokens.dart';

import '../../learning/domain/learning_session.dart';
import '../player_view_model.dart';
import 'playback_time_label.dart';

final class PlaybackControls extends StatefulWidget {
  const PlaybackControls({
    super.key,
    required this.state,
    required this.viewModel,
  });

  final PlayerViewState state;
  final PlayerViewModel viewModel;

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

final class _PlaybackControlsState extends State<PlaybackControls> {
  double? _dragPosition;

  String _modeLabel(CuePlaybackMode mode) => switch (mode) {
    CuePlaybackMode.continuous => '連續播放',
    CuePlaybackMode.pauseAfterCue => '逐句暫停',
    CuePlaybackMode.repeatCue => '單句循環',
  };

  IconData _modeIcon(CuePlaybackMode mode) => switch (mode) {
    CuePlaybackMode.continuous => Icons.playlist_play_rounded,
    CuePlaybackMode.pauseAfterCue => Icons.pause_circle_outline_rounded,
    CuePlaybackMode.repeatCue => Icons.repeat_one_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final viewModel = widget.viewModel;
    final playback = state.playback;
    final duration = playback?.durationMs;
    final position = _dragPosition?.round() ?? playback?.positionMs ?? 0;
    final canSeek = state.isReady && duration != null && duration > 0;
    final learning = state.learning;
    final mode = learning?.playbackMode ?? CuePlaybackMode.continuous;
    final intensive = learning?.mode == LearningMode.intensive;
    final theme = Theme.of(context);
    final editorial = EditorialColors.of(context);
    final playSize = MediaQuery.sizeOf(context).width >= EditorialSize.compact
        ? EditorialSize.desktopPlay
        : EditorialSize.mobilePlay;
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final speedControl = PopupMenuButton<double>(
      tooltip: '播放速度',
      enabled: state.isReady,
      initialValue: playback?.speed ?? 1,
      onSelected: (speed) => unawaited(viewModel.setSpeed(speed)),
      itemBuilder: (context) => [
        for (final speed in [0.5, 0.75, 0.9, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem(value: speed, child: Text('$speed×')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${playback?.speed ?? 1.0}×'),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
    final modeControl = PopupMenuButton<CuePlaybackMode>(
      tooltip: '播放模式',
      enabled: learning != null,
      initialValue: mode,
      onSelected: (mode) => unawaited(viewModel.setCuePlaybackMode(mode)),
      itemBuilder: (context) => [
        for (final option in CuePlaybackMode.values)
          PopupMenuItem(
            value: option,
            enabled:
                option != CuePlaybackMode.repeatCue ||
                learning?.currentCue != null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_modeIcon(option)),
              title: Text(_modeLabel(option)),
              trailing: option == mode ? const Icon(Icons.check) : null,
            ),
          ),
      ],
      child: Semantics(
        label: '目前播放模式：${_modeLabel(mode)}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_modeIcon(mode), size: 24),
              Text(_modeLabel(mode), style: timeStyle),
            ],
          ),
        ),
      ),
    );
    final intensiveControl = IconButton(
      tooltip: intensive ? '退出精聽' : '精聽',
      isSelected: intensive,
      onPressed: learning == null ? null : viewModel.toggleIntensiveMode,
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.school_outlined, size: 24),
          Text('精聽', style: timeStyle),
        ],
      ),
      selectedIcon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school, color: theme.colorScheme.primary, size: 24),
          Text(
            '精聽',
            style: timeStyle?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
    final primaryControls = SizedBox(
      width: 248,
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '上一句 (A / ←)',
                  onPressed: state.englishTrack == null
                      ? null
                      : () => unawaited(viewModel.previousCue()),
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  tooltip: '重播本句 (S)',
                  onPressed: learning?.currentCue == null
                      ? null
                      : () => unawaited(viewModel.replay()),
                  icon: const Icon(Icons.replay_rounded),
                ),
              ],
            ),
          ),
          IconButton.filled(
            key: const ValueKey('primaryPlayPauseButton'),
            tooltip: playback?.playing == true ? '暫停 (Space)' : '播放 (Space)',
            style: IconButton.styleFrom(
              fixedSize: Size(playSize, playSize),
              backgroundColor: editorial.primary,
              foregroundColor: editorial.onPrimary,
              disabledBackgroundColor: editorial.controlOutline.withValues(
                alpha: .22,
              ),
              disabledForegroundColor: editorial.textSecondary,
            ),
            onPressed: state.isReady
                ? () => unawaited(viewModel.togglePlayback())
                : null,
            icon: Icon(
              playback?.playing == true
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: state.isReady
                  ? editorial.onPrimary
                  : editorial.textSecondary,
              size: 24,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '下一句 (D / →)',
                onPressed: state.englishTrack == null
                    ? null
                    : () => unawaited(viewModel.nextCue()),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(playbackTimeLabel(position), style: timeStyle),
                Expanded(
                  child: Slider(
                    key: const ValueKey('playbackPositionSlider'),
                    min: 0,
                    max: (duration ?? 1).toDouble(),
                    value: canSeek
                        ? position.toDouble().clamp(0, duration.toDouble())
                        : 0,
                    semanticFormatterCallback: (value) =>
                        playbackTimeLabel(value.round()),
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
                Text(
                  duration == null ? '--:--' : playbackTimeLabel(duration),
                  style: timeStyle,
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= EditorialSize.compact &&
                    MediaQuery.textScalerOf(context).scale(12) <= 18;
                if (wide) {
                  return Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: speedControl,
                        ),
                      ),
                      primaryControls,
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [modeControl, intensiveControl],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    primaryControls,
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [speedControl, modeControl, intensiveControl],
                    ),
                  ],
                );
              },
            ),
            if (intensive)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    '精聽 · ${switch (learning!.phase) {
                      IntensivePhase.blindListening => '盲聽',
                      IntensivePhase.englishShown => '英文',
                      IntensivePhase.bilingualShown => '雙語',
                    }}',
                    style: timeStyle,
                  ),
                  ActionChip(
                    label: Text(switch (learning.phase) {
                      IntensivePhase.blindListening => '顯示英文',
                      IntensivePhase.englishShown => '顯示中文',
                      IntensivePhase.bilingualShown => '重新遮蔽',
                    }),
                    onPressed: viewModel.revealNext,
                  ),
                ],
              ),
            if (state.errorMessage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
