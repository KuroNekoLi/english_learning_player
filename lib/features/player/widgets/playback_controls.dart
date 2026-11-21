import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final viewModel = widget.viewModel;
    final playback = state.playback;
    final duration = playback?.durationMs;
    final position = _dragPosition?.round() ?? playback?.positionMs ?? 0;
    final canSeek = state.isReady && duration != null && duration > 0;
    final learning = state.learning;
    return Card(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(playbackTimeLabel(position)),
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
                Text(duration == null ? '--:--' : playbackTimeLabel(duration)),
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
                  onSelected: (speed) => unawaited(viewModel.setSpeed(speed)),
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
                if (learning != null && learning.mode != LearningMode.intensive)
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
