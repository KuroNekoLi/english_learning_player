import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/audio/speech_playback.dart';

final class DictionarySpeechButton extends ConsumerStatefulWidget {
  const DictionarySpeechButton({
    super.key,
    required this.text,
    required this.locale,
    required this.label,
    this.caption,
  });

  final String text;
  final String locale;
  final String label;
  final String? caption;

  @override
  ConsumerState<DictionarySpeechButton> createState() =>
      _DictionarySpeechButtonState();
}

final class _DictionarySpeechButtonState
    extends ConsumerState<DictionarySpeechButton> {
  final _owner = Object();
  SpeechPlayback? _playback;

  Future<void> _speak() async {
    final playback = ref.read(speechPlaybackProvider);
    _playback = playback;
    try {
      await playback.speak(_owner, widget.text, widget.locale);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('無法朗讀，請確認裝置或瀏覽器已提供此語言的語音。')),
      );
    }
  }

  @override
  void dispose() {
    final playback = _playback;
    if (playback != null) {
      unawaited(playback.stop(_owner).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.volume_up_outlined);
    if (widget.caption case final caption?) {
      return Tooltip(
        message: widget.label,
        child: TextButton.icon(
          onPressed: _speak,
          icon: icon,
          label: Text(caption),
        ),
      );
    }
    return IconButton(tooltip: widget.label, onPressed: _speak, icon: icon);
  }
}
