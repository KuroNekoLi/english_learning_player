import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/dictionary_repository.dart';
import '../dictionary_dependencies.dart';
import '../domain/word.dart';
import '../domain/original_word_context.dart';
import '../domain/saved_dictionary_word.dart';

final class DictionarySaveButton extends ConsumerStatefulWidget {
  const DictionarySaveButton({
    super.key,
    required this.word,
    this.originalContext,
  });
  final Word word;
  final OriginalWordContext? originalContext;

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
      await ref.read(updateSavedDictionaryWordProvider)(
        word,
        save: !saved,
        context: widget.originalContext,
      );
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
    if (!ref.watch(canEditWordBankProvider)) {
      return Tooltip(
        message: '目前登入的帳號只能檢視單字，請使用可編輯帳號加入或補加原句。',
        child: TextButton.icon(
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('唯讀帳號'),
        ),
      );
    }
    final words = ref.watch(savedDictionaryWordsProvider);
    final key = normalizeDictionaryWord(widget.word.word);
    final savedEntry = words.value == null
        ? null
        : _findSavedEntry(words.value!, key);
    final saved = savedEntry != null;
    final canAttachContext =
        saved &&
        savedEntry.originalContext == null &&
        widget.originalContext != null;
    return TextButton.icon(
      onPressed: _busy || words.isLoading || key.isEmpty
          ? null
          : words.hasError
          ? () => ref.invalidate(savedDictionaryWordsProvider)
          : canAttachContext
          ? () => _attachContext()
          : () => _toggle(saved),
      icon: Icon(
        canAttachContext
            ? Icons.add_link
            : saved
            ? Icons.bookmark_added
            : Icons.bookmark_add_outlined,
      ),
      label: Text(
        words.hasError
            ? '重試載入單字庫'
            : canAttachContext
            ? '補加這段原句'
            : saved
            ? '已加入單字庫 · 移除'
            : '加入單字庫',
      ),
    );
  }

  Future<void> _attachContext() async {
    final originalContext = widget.originalContext;
    if (originalContext == null) return;
    final word = widget.word;
    setState(() => _busy = true);
    try {
      await ref.read(updateSavedDictionaryWordProvider)(
        word,
        save: false,
        context: originalContext,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('單字庫更新失敗，請重試。')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SavedDictionaryWord? _findSavedEntry(
    List<SavedDictionaryWord> entries,
    String key,
  ) {
    for (final entry in entries) {
      if (normalizeDictionaryWord(entry.word.word) == key) return entry;
    }
    return null;
  }
}
