import 'word.dart';
import 'original_word_context.dart';

final class SavedDictionaryWord {
  const SavedDictionaryWord({required this.word, this.originalContext});

  final Word word;
  final OriginalWordContext? originalContext;

  String get key => word.word;
}
