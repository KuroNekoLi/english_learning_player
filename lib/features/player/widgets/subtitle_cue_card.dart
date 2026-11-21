import 'package:flutter/material.dart';

import '../../learning/domain/learning_session.dart';
import '../../subtitles/domain/subtitle_time.dart';
import '../../subtitles/domain/subtitle_timeline.dart';
import 'playback_time_label.dart';

final class SubtitleCueCard extends StatelessWidget {
  const SubtitleCueCard({
    super.key,
    required this.line,
    required this.offsetMs,
    required this.hasChineseTrack,
    required this.active,
    required this.visibility,
    required this.bookmarked,
    required this.onPlay,
    required this.onBookmark,
    required this.onRepeat,
    required this.onNext,
  });

  final SubtitleLine line;
  final int offsetMs;
  final bool hasChineseTrack;
  final bool active;
  final SubtitleVisibility visibility;
  final bool bookmarked;
  final VoidCallback onPlay;
  final VoidCallback onBookmark;
  final VoidCallback onRepeat;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final showEnglish =
        visibility == SubtitleVisibility.englishOnly ||
        visibility == SubtitleVisibility.bilingual;
    final showChinese =
        visibility == SubtitleVisibility.chineseOnly ||
        visibility == SubtitleVisibility.bilingual;
    final cue = line.cue;
    final start = subtitleToAudioMs(
      cue.startMs,
      offsetMs,
    ).clamp(0, 9007199254740991).toInt();
    final end = subtitleToAudioMs(
      cue.endMs,
      offsetMs,
    ).clamp(0, 9007199254740991).toInt();
    final timeRange = '${playbackTimeLabel(start)} – ${playbackTimeLabel(end)}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: active
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : Theme.of(context).colorScheme.surface,
      child: InkWell(
        key: active ? const ValueKey('activeSubtitleCard') : null,
        onTap: onPlay,
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
                      active ? '正在播放 · $timeRange' : timeRange,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (active)
                    IconButton(
                      tooltip: bookmarked ? '移除收藏' : '收藏本句',
                      onPressed: onBookmark,
                      icon: Icon(
                        bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    ),
                ],
              ),
              if (visibility == SubtitleVisibility.hidden)
                const Text('字幕已遮蔽')
              else ...[
                if (showEnglish)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line.english,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: active
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                if (showChinese)
                  if (line.translations.isEmpty)
                    if (hasChineseTrack ||
                        visibility == SubtitleVisibility.chineseOnly)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('未找到對應中文字幕'),
                      )
                    else
                      const SizedBox.shrink()
                  else
                    for (final translation in line.translations)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          translation.text,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: active
                                    ? Theme.of(context).colorScheme.onSurface
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
                        onPressed: onRepeat,
                        icon: const Icon(Icons.replay_rounded),
                      ),
                      IconButton(
                        tooltip: '下一句',
                        onPressed: onNext,
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
  }
}
