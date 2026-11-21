import 'dart:async';

import 'package:flutter/material.dart';

import '../../learning/domain/learning_session.dart';
import '../../subtitles/domain/subtitle_timeline.dart';
import 'subtitle_cue_card.dart';

final class SubtitleTranscript extends StatefulWidget {
  const SubtitleTranscript({
    super.key,
    required this.timeline,
    required this.visibility,
    required this.activeCueId,
    required this.intensive,
    required this.isCurrentCueBookmarked,
    required this.onPlayCue,
    required this.onBookmark,
    required this.onRepeatCue,
    required this.onNextCue,
  });

  final SubtitleTimeline timeline;
  final SubtitleVisibility visibility;
  final String? activeCueId;
  final bool intensive;
  final bool isCurrentCueBookmarked;
  final Future<void> Function(String cueId) onPlayCue;
  final Future<void> Function() onBookmark;
  final Future<void> Function() onRepeatCue;
  final Future<void> Function() onNextCue;

  @override
  State<SubtitleTranscript> createState() => _SubtitleTranscriptState();
}

final class _SubtitleTranscriptState extends State<SubtitleTranscript> {
  final _scrollController = ScrollController();
  final _rowKeys = <String, GlobalKey>{};
  String? _lastAutoScrolledCueId;
  double _averageRowExtent = 176;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _keepCurrentCueVisible();
    return ListView.builder(
      key: const ValueKey('subtitleTranscriptList'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      itemCount: widget.timeline.lines.length,
      itemBuilder: (context, index) {
        final line = widget.timeline.lines[index];
        final active = widget.activeCueId == line.cue.id;
        return SubtitleCueCard(
          key: _rowKeys.putIfAbsent(line.cue.id, GlobalKey.new),
          line: line,
          offsetMs: widget.timeline.offsetMs,
          hasChineseTrack: widget.timeline.hasChineseTrack,
          active: active,
          visibility: widget.intensive && !active
              ? SubtitleVisibility.hidden
              : widget.visibility,
          bookmarked: widget.isCurrentCueBookmarked,
          onPlay: () => unawaited(widget.onPlayCue(line.cue.id)),
          onBookmark: () => unawaited(widget.onBookmark()),
          onRepeat: () => unawaited(widget.onRepeatCue()),
          onNext: () => unawaited(widget.onNextCue()),
        );
      },
    );
  }

  void _keepCurrentCueVisible() {
    final activeCueId = widget.activeCueId;
    if (activeCueId == null) {
      _lastAutoScrolledCueId = null;
      return;
    }
    if (activeCueId == _lastAutoScrolledCueId) return;
    _lastAutoScrolledCueId = activeCueId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
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
