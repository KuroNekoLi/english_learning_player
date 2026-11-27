import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/audio/speech_playback.dart';
import '../../player/widgets/playback_time_label.dart';
import '../data/original_context_playback.dart';
import '../dictionary_dependencies.dart';
import '../domain/original_word_context.dart';

final class OriginalWordContextCard extends ConsumerStatefulWidget {
  const OriginalWordContextCard({
    super.key,
    required this.word,
    required this.originalContext,
  });

  final String word;
  final OriginalWordContext originalContext;

  @override
  ConsumerState<OriginalWordContextCard> createState() =>
      _OriginalWordContextCardState();
}

final class _OriginalWordContextCardState
    extends ConsumerState<OriginalWordContextCard> {
  final Object _speechOwner = Object();
  OriginalContextPlayback? _playback;
  SpeechPlayback? _speech;
  bool _loading = false;
  bool _playing = false;
  bool _speaking = false;
  bool _stopping = false;
  bool _forceTts = false;
  String? _unavailable;
  Future<OriginalContextAvailability>? _availability;

  @override
  void initState() {
    super.initState();
    _availability = _loadAvailability();
  }

  Future<OriginalContextAvailability> _loadAvailability() async {
    try {
      final playback = await ref.read(originalContextPlaybackProvider.future);
      _playback = playback;
      final result = await playback.availability(widget.originalContext);
      if (mounted) {
        setState(() => _unavailable = result.canPlay ? null : result.message);
      }
      return result;
    } catch (_) {
      const result = OriginalContextAvailability(false, '目前無法播放原音');
      if (mounted) setState(() => _unavailable = result.message);
      return result;
    }
  }

  Future<void> _activate() async {
    if (_loading || _speaking) return;
    if (_playing) {
      _stopping = true;
      final playback = _playback;
      if (playback != null) await playback.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final availability = await (_availability ?? _loadAvailability());
    if (!mounted) return;
    if (!availability.canPlay || _forceTts) {
      await _speak();
      return;
    }
    final playback = _playback;
    if (playback == null) {
      setState(() => _unavailable = '目前無法播放原音');
      return;
    }
    final speech = ref.read(speechPlaybackProvider);
    _speech = speech;
    await speech.stop(_speechOwner);
    setState(() => _loading = true);
    final task = playback.play(
      widget.originalContext,
      onStarted: () {
        if (mounted) {
          setState(() {
            _loading = false;
            _playing = true;
          });
        }
      },
    );
    final result = await task;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _playing = false;
      if (!result && !_stopping) {
        _unavailable = '目前無法播放原音';
        _forceTts = true;
      }
    });
    _stopping = false;
  }

  Future<void> _speak() async {
    if (_speaking) return;
    final contextPlayback = _playback;
    if (contextPlayback != null) await contextPlayback.stop();
    final playback = ref.read(speechPlaybackProvider);
    _speech = playback;
    setState(() => _speaking = true);
    try {
      await playback.speak(
        _speechOwner,
        widget.originalContext.english,
        'en-US',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('無法朗讀，請確認裝置的英文語音設定。')));
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  void dispose() {
    final playback = _playback;
    if (playback != null && (_loading || _playing)) {
      unawaited(playback.stop());
    }
    final speech = _speech;
    if (speech != null) unawaited(speech.stop(_speechOwner));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12, bottom: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('原句', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            '${widget.originalContext.materialTitle} · '
            '${playbackTimeLabel(widget.originalContext.startMs)}–'
            '${playbackTimeLabel(widget.originalContext.endMs)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _HighlightedOriginalSentence(
            text: widget.originalContext.english,
            word: widget.word,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final translation in widget.originalContext.translations)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                translation,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FutureBuilder<OriginalContextAvailability>(
              future: _availability,
              builder: (context, snapshot) {
                final available =
                    (snapshot.data?.canPlay ?? false) && !_forceTts;
                final label = _loading
                    ? '載入原音中'
                    : _playing
                    ? '停止'
                    : _speaking
                    ? '正在朗讀'
                    : available && _unavailable == null
                    ? '播放原音'
                    : '朗讀原句';
                return TextButton.icon(
                  onPressed: _loading || _speaking ? null : _activate,
                  icon: _loading || _speaking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_playing ? Icons.stop : Icons.volume_up_outlined),
                  label: Text(label),
                );
              },
            ),
          ),
          if (_unavailable case final message?)
            Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

final class _HighlightedOriginalSentence extends StatelessWidget {
  const _HighlightedOriginalSentence({
    required this.text,
    required this.word,
    required this.style,
  });

  final String text;
  final String word;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final token = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in token.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final matched = match.group(0)!;
      final isWord = _normalize(matched) == _normalize(word);
      spans.add(
        TextSpan(
          text: matched,
          style: isWord
              ? TextStyle(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  fontWeight: FontWeight.w700,
                )
              : null,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(style: style, children: spans));
  }

  String _normalize(String value) => value.toLowerCase().replaceAll('’', "'");
}
