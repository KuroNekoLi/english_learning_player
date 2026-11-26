import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/dictionary_repository.dart';
import '../dictionary_dependencies.dart';
import '../domain/word.dart';

final class DictionarySaveButton extends ConsumerStatefulWidget {
  const DictionarySaveButton({super.key, required this.word});
  final Word word;

  @override
  ConsumerState<DictionarySaveButton> createState() =>
      _DictionarySaveButtonState();
}

final class _DictionarySaveButtonState
    extends ConsumerState<DictionarySaveButton> {
  bool _busy = false;

  Future<void> _toggle(bool saved) async {
    final word = widget.word;
    setState(() => _busy = true);
    try {
      await ref.read(updateSavedDictionaryWordProvider)(word, save: !saved);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('單字庫更新失敗，請重試。')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(canEditWordBankProvider)) return const SizedBox.shrink();
    final words = ref.watch(savedDictionaryWordsProvider);
    final key = normalizeDictionaryWord(widget.word.word);
    final saved =
        words.value?.any(
          (entry) => normalizeDictionaryWord(entry.word) == key,
        ) ??
        false;
    return TextButton.icon(
      onPressed: _busy || words.isLoading || key.isEmpty
          ? null
          : words.hasError
          ? () => ref.invalidate(savedDictionaryWordsProvider)
          : () => _toggle(saved),
      icon: Icon(saved ? Icons.bookmark_added : Icons.bookmark_add_outlined),
      label: Text(
        words.hasError
            ? '重試載入單字庫'
            : saved
            ? '已加入單字庫 · 移除'
            : '加入單字庫',
      ),
    );
  }
}
