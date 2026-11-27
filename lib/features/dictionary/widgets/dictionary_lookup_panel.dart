import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../dictionary_dependencies.dart';
import '../domain/word.dart';
import '../domain/original_word_context.dart';
import 'dictionary_save_button.dart';
import 'dictionary_speech_button.dart';
import 'original_word_context_card.dart';

final class DictionaryLookupPanel extends ConsumerStatefulWidget {
  const DictionaryLookupPanel({
    super.key,
    required this.word,
    required this.onClose,
    this.originalContext,
  });
  final String word;
  final VoidCallback onClose;
  final OriginalWordContext? originalContext;

  @override
  ConsumerState<DictionaryLookupPanel> createState() =>
      _DictionaryLookupPanelState();
}

final class _DictionaryLookupPanelState
    extends ConsumerState<DictionaryLookupPanel> {
  late Future<Word> _lookup;

  @override
  void initState() {
    super.initState();
    _startLookup();
  }

  void _startLookup() {
    _lookup = ref
        .read(dictionaryRepositoryProvider.future)
        .then((repository) => repository.lookupWord(widget.word));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.word,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '關閉單字查詢',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Flexible(
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
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                  ),
                );
              }
              return DictionaryWordDetails(
                word: snapshot.data!,
                originalContext: widget.originalContext,
              );
            },
          ),
        ),
      ],
    ),
  );
}

final class DictionaryWordDetails extends StatelessWidget {
  const DictionaryWordDetails({
    super.key,
    required this.word,
    this.originalContext,
    this.showOriginalContextCard = false,
  });
  final Word word;
  final OriginalWordContext? originalContext;
  final bool showOriginalContextCard;

  @override
  Widget build(BuildContext context) {
    final senseCount = word.entries.fold(
      0,
      (total, entry) => total + entry.definitions.length,
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pronunciationLabel(word.pronunciations) case final label?)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(label)),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DictionarySpeechButton(
                text: word.word,
                locale: 'en-GB',
                label: '英式發音',
                caption: '英式',
              ),
              DictionarySpeechButton(
                text: word.word,
                locale: 'en-US',
                label: '美式發音',
                caption: '美式',
              ),
              DictionarySaveButton(
                word: word,
                originalContext: originalContext,
              ),
            ],
          ),
          if (showOriginalContextCard)
            if (originalContext case final context?)
              OriginalWordContextCard(
                word: word.word,
                originalContext: context,
              ),
          if (showOriginalContextCard && originalContext == null)
            const _MissingOriginalContextNotice(),
          if (senseCount > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('收錄 $senseCount 個詞義'),
            ),
          const SizedBox(height: 12),
          for (final entry in word.entries) ...[
            Text(
              entry.partOfSpeech,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final (index, definition) in entry.definitions.indexed) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (definition.zhDefinition.trim().isNotEmpty)
                      definition.zhDefinition,
                    if (definition.enDefinition.trim().isNotEmpty)
                      definition.enDefinition,
                  ].join('\n').withSenseNumber(index, entry.definitions.length),
                ),
              ),
              for (final example in definition.examples)
                _DictionaryExample(example: example),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

final class _MissingOriginalContextNotice extends ConsumerWidget {
  const _MissingOriginalContextNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canEditWordBankProvider);
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('尚未保存原句'),
        subtitle: Text(
          canEdit
              ? '到這個單字出現的字幕長按它，再選「補加這段原句」，即可保存原音片段。'
              : '目前是唯讀帳號，無法補加原句；請使用可編輯帳號操作。',
        ),
      ),
    );
  }
}

extension on String {
  String withSenseNumber(int index, int count) =>
      count > 1 ? '${index + 1}. $this' : this;
}

final class _DictionaryExample extends StatelessWidget {
  const _DictionaryExample({required this.example});

  final WordExample example;

  @override
  Widget build(BuildContext context) {
    final source = example.source;
    final lines = example.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '“$line”',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                DictionarySpeechButton(
                  text: line,
                  locale: _hasHan.hasMatch(line) ? 'zh-TW' : 'en-US',
                  label: _hasHan.hasMatch(line) ? '朗讀中文例句' : '朗讀英文例句',
                ),
              ],
            ),
          if (source != null && example.sourceUrl == null)
            Text(source, style: Theme.of(context).textTheme.bodySmall)
          else if (source != null)
            TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(source),
                    content: SelectableText(
                      [
                        ?example.author,
                        ?example.sourceUrl,
                        ?example.licenseUrl,
                        '中文統一為台灣繁體。',
                      ].join('\n'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('關閉'),
                      ),
                    ],
                  ),
                );
              },
              child: Text([source, ?example.author].join(' · ')),
            ),
        ],
      ),
    );
  }
}

final _hasHan = RegExp(r'\p{Script=Han}', unicode: true);

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
