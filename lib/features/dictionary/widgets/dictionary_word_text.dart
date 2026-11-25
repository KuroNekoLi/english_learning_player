import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dictionary_dependencies.dart';
import '../domain/word.dart';

/// Renders a subtitle with tap-to-highlight full-word lookup.
final class DictionaryWordText extends StatefulWidget {
  const DictionaryWordText({
    super.key,
    required this.text,
    required this.style,
    this.onWordSelected,
    this.lookupOnTap = true,
  });

  final String text;
  final TextStyle? style;
  final ValueChanged<String>? onWordSelected;
  final bool lookupOnTap;

  @override
  State<DictionaryWordText> createState() => _DictionaryWordTextState();
}

final class _DictionaryWordTextState extends State<DictionaryWordText> {
  String? _selectedWord;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final matches = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*")
          .allMatches(widget.text)
          .toList(growable: false);
      final children = <TextSpan>[];
      var cursor = 0;
      for (final match in matches) {
        if (match.start > cursor) {
          children.add(
            TextSpan(text: widget.text.substring(cursor, match.start)),
          );
        }
        final word = match.group(0)!;
        children.add(
          TextSpan(
            text: word,
            style: word.toLowerCase() == _selectedWord
                ? const TextStyle(
                    backgroundColor: Color(0x663F8CFF),
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
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (event) {
          final position = painter
              .getPositionForOffset(event.localPosition)
              .offset;
          for (final match in matches) {
            if (position >= match.start && position <= match.end) {
              final word = match.group(0)!.toLowerCase();
              setState(() => _selectedWord = word);
              final onWordSelected = widget.onWordSelected;
              onWordSelected?.call(word);
              if (widget.lookupOnTap) _showLookup(word, event.globalPosition);
              return;
            }
          }
        },
        child: Text.rich(
          TextSpan(style: widget.style, children: children),
          textScaler: MediaQuery.textScalerOf(context),
        ),
      );
    },
  );

  Future<void> _showLookup(String word, Offset globalPosition) =>
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '關閉單字查詢',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (dialogContext, _, _) {
          final overlay =
              Overlay.of(dialogContext).context.findRenderObject()!
                  as RenderBox;
          final anchor = overlay.globalToLocal(globalPosition);
          final size = MediaQuery.sizeOf(dialogContext);
          final width = size.width < 440 ? size.width - 24 : 400.0;
          final left = anchor.dx.clamp(12.0, size.width - width - 12);
          final top = anchor.dy + 16 + 320 < size.height
              ? anchor.dy + 16
              : (anchor.dy - 336).clamp(12.0, size.height - 324);
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: DictionaryLookupPanel(word: word),
                ),
              ),
            ],
          );
        },
      );
}

final class DictionaryLookupPanel extends ConsumerStatefulWidget {
  const DictionaryLookupPanel({super.key, required this.word});
  final String word;

  @override
  ConsumerState<DictionaryLookupPanel> createState() =>
      _DictionaryLookupPanelState();
}

final class _DictionaryLookupPanelState
    extends ConsumerState<DictionaryLookupPanel> {
  late Future<Word> _lookup;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _startLookup();
  }

  void _startLookup() {
    final generation = ++_generation;
    _lookup = ref
        .read(dictionaryRepositoryProvider.future)
        .then((repository) => repository.lookupWord(widget.word));
    _lookup = _lookup.then((word) {
      if (generation != _generation) throw StateError('Lookup was replaced.');
      return word;
    });
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<Word>(
        future: _lookup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              heightFactor: 2,
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.word,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('目前無法取得單字資料，請檢查網路後重試。'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(_startLookup),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重試'),
                  ),
                ),
              ],
            );
          }
          return _WordDetails(word: snapshot.data!);
        },
      ),
    ),
  );
}

final class _WordDetails extends StatelessWidget {
  const _WordDetails({required this.word});
  final Word word;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(word.word, style: Theme.of(context).textTheme.titleLarge),
        if (_pronunciationLabel(word.pronunciations) case final label?)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(label)),
        const SizedBox(height: 12),
        for (final entry in word.entries) ...[
          Text(
            entry.partOfSpeech,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final definition in entry.definitions) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                definition.enDefinition.trim().isEmpty
                    ? definition.zhDefinition
                    : '${definition.zhDefinition}\n${definition.enDefinition}',
              ),
            ),
            for (final example in definition.examples)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 3),
                child: Text(
                  '“$example”',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ],
    ),
  );
}

String? _pronunciationLabel(WordPronunciations pronunciations) {
  final labels = <String>[];
  final uk = pronunciations.uk;
  final us = pronunciations.us;
  final phonetic = pronunciations.phonetic;
  if (uk != null && uk.trim().isNotEmpty) labels.add('英 $uk');
  if (us != null && us.trim().isNotEmpty) labels.add('美 $us');
  if (labels.isEmpty && phonetic != null && phonetic.trim().isNotEmpty) {
    labels.add('音標 $phonetic');
  }
  return labels.isEmpty ? null : labels.join('  ·  ');
}
