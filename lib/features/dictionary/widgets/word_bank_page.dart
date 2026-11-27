import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design_system/editorial_components.dart';
import '../../../core/design_system/editorial_typography.dart';

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

final class WordBankPage extends ConsumerStatefulWidget {
  const WordBankPage({super.key});

  @override
  ConsumerState<WordBankPage> createState() => _WordBankPageState();
}

final class _WordBankPageState extends ConsumerState<WordBankPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的單字庫')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ref
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
                final query = _query.trim().toLowerCase();
                final visible = words
                    .where(
                      (entry) =>
                          query.isEmpty ||
                          entry.word.word.toLowerCase().contains(query) ||
                          entry.word.entries.any(
                            (sense) => sense.definitions.any(
                              (def) =>
                                  def.zhDefinition.contains(query) ||
                                  def.enDefinition.toLowerCase().contains(
                                    query,
                                  ),
                            ),
                          ),
                    )
                    .toList();
                return Column(
                  children: [
                    EditorialPageHeading(
                      eyebrow: 'VOCABULARY',
                      title: '我的單字',
                      subtitle: '已收藏 ${words.length} 個單字',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '搜尋單字',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: words.isEmpty
                          ? const Center(child: Text('還沒有收藏單字。可從字典查詢加入。'))
                          : visible.isEmpty
                          ? const Center(child: Text('沒有符合的單字'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final word = visible[index].word;
                                final glosses = [
                                  for (final entry in word.entries)
                                    for (final definition in entry.definitions)
                                      if (definition.zhDefinition
                                          .trim()
                                          .isNotEmpty)
                                        definition.zhDefinition,
                                ];
                                return EditorialListRow(
                                  child: ListTile(
                                    title: Text(
                                      word.word,
                                      style: EditorialTypography.english(
                                        context,
                                        size: 24,
                                      ),
                                    ),
                                    subtitle: glosses.isEmpty
                                        ? null
                                        : Text(
                                            glosses.first,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            _SavedWordPage(word: word),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    ),
  );
}

final class _SavedWordPage extends ConsumerWidget {
  const _SavedWordPage({required this.word});
  final Word word;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(
        word.word,
        style: EditorialTypography.english(context, size: 28),
      ),
    ),
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
