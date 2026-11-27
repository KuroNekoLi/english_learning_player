import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'dictionary_lookup_panel.dart';
import '../domain/original_word_context.dart';

/// The transcript shares one coordinator so only one cue can open a popup.
final class DictionaryLookupCoordinator {
  VoidCallback? _dismiss;

  void show(VoidCallback dismiss) {
    if (_dismiss == dismiss) return;
    close();
    _dismiss = dismiss;
  }

  void forget(VoidCallback dismiss) {
    if (_dismiss == dismiss) _dismiss = null;
  }

  void close() {
    final dismiss = _dismiss;
    _dismiss = null;
    dismiss?.call();
  }
}

final class DictionaryWordText extends StatefulWidget {
  const DictionaryWordText({
    super.key,
    required this.text,
    required this.style,
    this.coordinator,
    this.originalContext,
  });

  final String text;
  final TextStyle? style;
  final DictionaryLookupCoordinator? coordinator;
  final OriginalWordContext? originalContext;

  @override
  State<DictionaryWordText> createState() => _DictionaryWordTextState();
}

typedef _LookupTarget = ({String word, int start, Rect bounds});

final class _DictionaryWordTextState extends State<DictionaryWordText> {
  static final _words = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");
  final _paragraph = GlobalKey();
  final _portal = OverlayPortalController();
  Timer? _hoverTimer;
  Timer? _dismissTimer;
  _LookupTarget? _hoverTarget;
  _LookupTarget? _selected;
  bool _pinned = false;

  @override
  void didUpdateWidget(DictionaryWordText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      final previous = _selected;
      _cancelHover();
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_selected, previous)) _hide();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.coordinator?.forget(_hide);
    _cancelHover();
    _dismissTimer?.cancel();
    super.dispose();
  }

  _LookupTarget? _targetAt(Offset globalPosition) {
    final box = _paragraph.currentContext?.findRenderObject();
    if (box is! RenderParagraph || !box.hasSize) return null;
    final position = box.globalToLocal(globalPosition);
    final offset = box.getPositionForOffset(position).offset;
    for (final match in _words.allMatches(widget.text)) {
      if (offset < match.start || offset > match.end) continue;
      final boxes = box.getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      for (final textBox in boxes) {
        final rect = textBox.toRect();
        if (!rect.contains(position)) continue;
        return (
          word: match.group(0)!.toLowerCase(),
          start: match.start,
          bounds: Rect.fromPoints(
            box.localToGlobal(rect.topLeft),
            box.localToGlobal(rect.bottomRight),
          ),
        );
      }
    }
    return null;
  }

  void _hover(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _pinned) return;
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return;
    }
    final target = _targetAt(event.position);
    if (target == null) {
      _cancelHover();
      _scheduleDismiss();
      return;
    }
    _dismissTimer?.cancel();
    if (_selected == target) {
      _cancelHover();
      return;
    }
    if (_hoverTarget == target) return;
    _cancelHover();
    _hoverTarget = target;
    _hoverTimer = Timer(const Duration(milliseconds: 350), () {
      _hoverTarget = null;
      if (mounted && _targetAt(event.position) == target) _show(target);
    });
  }

  void _cancelHover() {
    _hoverTimer?.cancel();
    _hoverTarget = null;
  }

  void _scheduleDismiss() {
    if (_pinned || _selected == null || (_dismissTimer?.isActive ?? false)) {
      return;
    }
    _dismissTimer = Timer(const Duration(milliseconds: 300), _hide);
  }

  void _show(_LookupTarget target, {bool pinned = false}) {
    _cancelHover();
    _dismissTimer?.cancel();
    widget.coordinator?.show(_hide);
    setState(() {
      _selected = target;
      _pinned = pinned;
    });
    _portal.show();
  }

  void _hide() {
    _cancelHover();
    _dismissTimer?.cancel();
    widget.coordinator?.forget(_hide);
    if (_selected == null || !mounted) return;
    setState(() {
      _selected = null;
      _pinned = false;
    });
    _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final children = <TextSpan>[];
    var cursor = 0;
    for (final match in _words.allMatches(widget.text)) {
      if (match.start > cursor) {
        children.add(
          TextSpan(text: widget.text.substring(cursor, match.start)),
        );
      }
      children.add(
        TextSpan(
          text: match.group(0),
          style: match.start == _selected?.start
              ? TextStyle(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  decoration: TextDecoration.underline,
                )
              : null,
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildPopup,
      child: MouseRegion(
        onEnter: _hover,
        onHover: _hover,
        onExit: (_) {
          _cancelHover();
          _scheduleDismiss();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (event) {
            final target = _targetAt(event.globalPosition);
            if (target != null) _show(target, pinned: true);
          },
          child: Text.rich(
            TextSpan(style: widget.style, children: children),
            key: _paragraph,
          ),
        ),
      ),
    );
  }

  Widget _buildPopup(BuildContext context) {
    final target = _selected;
    if (target == null) return const SizedBox.shrink();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final word = target.bounds;
    final upper = overlay.globalToLocal(word.topLeft);
    final lower = overlay.globalToLocal(word.bottomLeft);

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        final minX = padding.left + 8;
        final maxX = constraints.maxWidth - padding.right - 8;
        final minY = padding.top + 8;
        final maxY = constraints.maxHeight - padding.bottom - 8;
        if (maxX <= minX || maxY <= minY) return const SizedBox.shrink();
        final width = math.min(400.0, maxX - minX);
        final below = (lower.dy + 6).clamp(minY, maxY).toDouble();
        final above = (upper.dy - 6).clamp(minY, maxY).toDouble();
        final openBelow = maxY - below >= math.min(340, above - minY);
        final height = math.min(340.0, openBelow ? maxY - below : above - minY);
        return Stack(
          children: [
            Positioned(
              left: upper.dx.clamp(minX, maxX - width).toDouble(),
              top: openBelow ? below : null,
              bottom: openBelow ? null : constraints.maxHeight - above,
              width: width,
              child: TapRegion(
                onTapOutside: (_) => _hide(),
                child: MouseRegion(
                  onEnter: (_) {
                    _cancelHover();
                    _dismissTimer?.cancel();
                  },
                  onExit: (_) => _scheduleDismiss(),
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height),
                      child: DictionaryLookupPanel(
                        key: ValueKey(target.word),
                        word: target.word,
                        originalContext: widget.originalContext,
                        onClose: _hide,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
