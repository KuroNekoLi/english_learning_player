import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../dictionary_dependencies.dart';
import '../domain/saved_dictionary_word.dart';
import '../domain/word.dart';
import 'dictionary_lookup_panel.dart';

final class OpenWordBankButton extends StatelessWidget {
  const OpenWordBankButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '我的單字庫',
    icon: const Icon(Icons.collections_bookmark_outlined),
    onPressed: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const WordBankPage())),
  );
}

final class WordBankPage extends ConsumerWidget {
  const WordBankPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('我的單字庫')),
    body: ref
        .watch(savedDictionaryWordsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(savedDictionaryWordsProvider),
              child: const Text('單字庫載入失敗，重試'),
            ),
          ),
          data: (words) => words.isEmpty
              ? const Center(child: Text('還沒有收藏單字。可從字典查詢加入。'))
              : ListView.builder(
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    final word = words[index].word;
                    final glosses = [
                      for (final entry in word.entries)
                        for (final definition in entry.definitions)
                          if (definition.zhDefinition.trim().isNotEmpty)
                            definition.zhDefinition,
                    ];
                    return ListTile(
                      title: Text(word.word),
                      subtitle: glosses.isEmpty
                          ? null
                          : Text(
                              glosses.first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _SavedWordPage(word: word),
                        ),
                      ),
                    );
                  },
                ),
        ),
  );
}

final class _SavedWordPage extends ConsumerWidget {
  const _SavedWordPage({required this.word});
  final Word word;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(word.word)),
    body: ref
        .watch(savedDictionaryWordsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(savedDictionaryWordsProvider),
              child: const Text('單字庫載入失敗，重試'),
            ),
          ),
          data: (words) {
            SavedDictionaryWord? saved;
            for (final entry in words) {
              if (entry.word.word.toLowerCase() == word.word.toLowerCase()) {
                saved = entry;
                break;
              }
            }
            return Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DictionaryWordDetails(
                    word: saved?.word ?? word,
                    originalContext: saved?.originalContext,
                    showOriginalContextCard: true,
                  ),
                ),
              ),
            );
          },
        ),
  );
}
