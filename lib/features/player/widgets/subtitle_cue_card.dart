import 'package:material_ui/material_ui.dart';

import '../../learning/domain/learning_session.dart';
import '../../dictionary/domain/original_word_context.dart';
import '../../dictionary/widgets/dictionary_word_text.dart';
import '../../subtitles/domain/subtitle_time.dart';
import '../../subtitles/domain/subtitle_timeline.dart';
import 'playback_time_label.dart';

final class SubtitleCueCard extends StatelessWidget {
  const SubtitleCueCard({
    super.key,
    required this.line,
    this.originalContext,
    required this.offsetMs,
    required this.hasChineseTrack,
    required this.active,
    required this.playing,
    required this.visibility,
    required this.bookmarked,
    required this.onPlay,
    required this.onBookmark,
    this.dictionaryLookup,
  });

  final SubtitleLine line;
  final OriginalWordContext? originalContext;
  final int offsetMs;
  final bool hasChineseTrack;
  final bool active;
  final bool playing;
  final SubtitleVisibility visibility;
  final bool bookmarked;
  final VoidCallback onPlay;
  final VoidCallback onBookmark;
  final DictionaryLookupCoordinator? dictionaryLookup;

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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: active
          ? colors.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: active ? const ValueKey('activeSubtitleCard') : null,
        onTap: onPlay,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: playing ? '暫停本句' : '播放本句',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onPlay,
                color: active ? colors.primary : colors.onSurfaceVariant,
                icon: Icon(
                  playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_outline,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, bottom: 2),
                      child: Text(
                        active
                            ? '$timeRange · ${playing ? '播放中' : '已暫停'}'
                            : timeRange,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (visibility == SubtitleVisibility.hidden)
                      const Text('字幕已遮蔽')
                    else ...[
                      if (showEnglish)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: DictionaryWordText(
                            text: line.english
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim(),
                            coordinator: dictionaryLookup,
                            originalContext: originalContext,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 19,
                                  height: 1.45,
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
                                translation.text
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      height: 1.5,
                                    ),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                child: active
                    ? IconButton(
                        tooltip: bookmarked ? '移除收藏' : '收藏本句',
                        onPressed: onBookmark,
                        color: colors.onSurfaceVariant,
                        iconSize: 20,
                        icon: Icon(
                          bookmarked ? Icons.bookmark : Icons.bookmark_border,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
