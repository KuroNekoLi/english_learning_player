import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';

import '../../dictionary/widgets/dictionary_word_text.dart';
import '../../dictionary/domain/original_word_context.dart';
import '../../learning/domain/learning_session.dart';
import '../../subtitles/domain/subtitle_time.dart';
import '../../subtitles/domain/subtitle_timeline.dart';
import 'subtitle_cue_card.dart';
import '../subtitle_style.dart';

final class SubtitleTranscript extends StatefulWidget {
  const SubtitleTranscript({
    super.key,
    required this.timeline,
    this.style = const SubtitleStyle(),
    this.savedWords = const {},
    required this.materialId,
    required this.materialTitle,
    required this.visibility,
    required this.activeCueId,
    required this.intensive,
    required this.isCurrentCueBookmarked,
    required this.onPlayCue,
    required this.onBookmark,
    required this.playing,
    required this.onTogglePlayback,
  });

  final SubtitleTimeline timeline;
  final SubtitleStyle style;
  final Set<String> savedWords;
  final String materialId;
  final String materialTitle;
  final SubtitleVisibility visibility;
  final String? activeCueId;
  final bool intensive;
  final bool isCurrentCueBookmarked;
  final Future<void> Function(String cueId) onPlayCue;
  final Future<void> Function() onBookmark;
  final bool playing;
  final Future<void> Function() onTogglePlayback;

  @override
  State<SubtitleTranscript> createState() => _SubtitleTranscriptState();
}

final class _SubtitleTranscriptState extends State<SubtitleTranscript> {
  final _scrollController = ScrollController();
  final _dictionaryLookup = DictionaryLookupCoordinator();
  final _rowKeys = <String, GlobalKey>{};
  String? _lastAutoScrolledCueId;
  double _averageRowExtent = 110;
  bool _following = true;
  bool _activeOffscreen = false;
  final _viewportKey = GlobalKey();
  bool _visibilityCheckScheduled = false;
  void _checkVisibility() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted || _following) return;
      final id = widget.activeCueId;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      final row = id == null
          ? null
          : _rowKeys[id]?.currentContext?.findRenderObject();
      var offscreen = id != null;
      if (viewport is RenderBox &&
          row is RenderBox &&
          viewport.hasSize &&
          row.hasSize) {
        final viewRect = viewport.localToGlobal(Offset.zero) & viewport.size;
        final rowRect = row.localToGlobal(Offset.zero) & row.size;
        offscreen = !viewRect.overlaps(rowRect);
      }
      if (offscreen != _activeOffscreen) {
        setState(() => _activeOffscreen = offscreen);
      }
    });
  }

  final _translationOverrides = <String>{};

  @override
  void didUpdateWidget(SubtitleTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibility != widget.visibility ||
        oldWidget.intensive != widget.intensive ||
        oldWidget.materialId != widget.materialId ||
        oldWidget.timeline != widget.timeline) {
      _translationOverrides.clear();
    }
    if (oldWidget.style != widget.style) _lastAutoScrolledCueId = null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _keepCurrentCueVisible();
    if (!_following) _checkVisibility();
    return Stack(
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && _following) {
              setState(() => _following = false);
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0) return false;
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null &&
                  _following) {
                setState(() => _following = false);
              }
              _checkVisibility();
              if (notification is ScrollStartNotification) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _dictionaryLookup.close();
                });
              }
              return false;
            },
            child: SizedBox.expand(
              key: _viewportKey,
              child: ListView.builder(
                key: const ValueKey('subtitleTranscriptList'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: widget.timeline.lines.length,
                itemBuilder: (context, index) {
                  final line = widget.timeline.lines[index];
                  final active = widget.activeCueId == line.cue.id;
                  final startMs = subtitleToAudioMs(
                    line.cue.startMs,
                    widget.timeline.offsetMs,
                  );
                  final endMs = subtitleToAudioMs(
                    line.cue.endMs,
                    widget.timeline.offsetMs,
                  );
                  final originalContext =
                      endMs > startMs && line.english.trim().isNotEmpty
                      ? OriginalWordContext(
                          materialId: widget.materialId,
                          materialTitle: widget.materialTitle,
                          startMs: startMs < 0 ? 0 : startMs,
                          endMs: endMs,
                          english: line.english.trim(),
                          translations: [
                            for (final translation in line.translations)
                              if (translation.text.trim().isNotEmpty)
                                translation.text.trim(),
                          ],
                        )
                      : null;
                  final canToggleTranslation =
                      !widget.intensive &&
                      (widget.visibility == SubtitleVisibility.englishOnly ||
                          widget.visibility == SubtitleVisibility.bilingual) &&
                      line.translations.any((t) => t.text.trim().isNotEmpty);
                  final overridden = _translationOverrides.contains(
                    line.cue.id,
                  );
                  return SubtitleCueCard(
                    dictionaryLookup: _dictionaryLookup,
                    key: _rowKeys.putIfAbsent(line.cue.id, GlobalKey.new),
                    line: line,
                    style: widget.style,
                    savedWords: widget.savedWords,
                    translationOverride: canToggleTranslation && overridden,
                    onToggleTranslation: canToggleTranslation
                        ? () => setState(() {
                            if (!_translationOverrides.remove(line.cue.id)) {
                              _translationOverrides.add(line.cue.id);
                            }
                          })
                        : null,
                    originalContext: originalContext,
                    offsetMs: widget.timeline.offsetMs,
                    hasChineseTrack: widget.timeline.hasChineseTrack,
                    active: active,
                    playing: active && widget.playing,
                    visibility: widget.intensive && !active
                        ? SubtitleVisibility.hidden
                        : widget.visibility,
                    bookmarked: widget.isCurrentCueBookmarked,
                    onPlay: () {
                      setState(() {
                        _following = true;
                        _lastAutoScrolledCueId = null;
                      });
                      if (active) {
                        unawaited(widget.onTogglePlayback());
                      } else {
                        unawaited(widget.onPlayCue(line.cue.id));
                      }
                    },
                    onBookmark: () => unawaited(widget.onBookmark()),
                  );
                },
              ),
            ),
          ),
        ),
        if (!_following && _activeOffscreen)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _following = true;
                  _lastAutoScrolledCueId = null;
                }),
                icon: const Icon(Icons.my_location),
                label: const Text('回到播放位置'),
              ),
            ),
          ),
      ],
    );
  }

  void _keepCurrentCueVisible() {
    if (!_following) return;
    final activeCueId = widget.activeCueId;
    if (activeCueId == null) {
      _lastAutoScrolledCueId = null;
      return;
    }
    if (activeCueId == _lastAutoScrolledCueId) return;
    _lastAutoScrolledCueId = activeCueId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_following ||
          !_scrollController.hasClients ||
          widget.activeCueId != activeCueId) {
        return;
      }
      _refreshAverageRowExtent();
      final targetKey = _rowKeys[activeCueId];
      final targetContext = targetKey?.currentContext;
      if (targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.42,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
          ),
        );
        return;
      }

      // A seek can jump to a cue that has never been built by the lazy list.
      // Estimate its position, then the next frame can ensure it precisely.
      final index = widget.timeline.indexOf(activeCueId);
      if (index == null) return;
      _scrollToEstimatedIndex(index, activeCueId, attemptsRemaining: 4);
    });
  }

  void _scrollToEstimatedIndex(
    int targetIndex,
    String cueId, {
    required int attemptsRemaining,
  }) {
    if (!mounted ||
        !_following ||
        !_scrollController.hasClients ||
        widget.activeCueId != cueId) {
      return;
    }
    final targetContext = _rowKeys[cueId]?.currentContext;
    if (targetContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.42,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        ),
      );
      return;
    }
    if (attemptsRemaining == 0) return;
    final position = _scrollController.position;
    final estimatedIndex = position.pixels / _averageRowExtent;
    final correction = (targetIndex - estimatedIndex) * _averageRowExtent;
    _scrollController.jumpTo(
      (position.pixels + correction).clamp(0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.activeCueId != cueId) return;
      _refreshAverageRowExtent();
      _scrollToEstimatedIndex(
        targetIndex,
        cueId,
        attemptsRemaining: attemptsRemaining - 1,
      );
    });
  }

  void _refreshAverageRowExtent() {
    final heights = _rowKeys.values
        .map((key) => key.currentContext?.findRenderObject())
        .whereType<RenderBox>()
        .where((box) => box.hasSize)
        .map((box) => box.size.height)
        .toList(growable: false);
    if (heights.isEmpty) return;
    _averageRowExtent =
        heights.reduce((total, height) => total + height) / heights.length + 12;
  }
}
