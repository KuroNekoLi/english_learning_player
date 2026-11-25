import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/local_database.dart';
import '../domain/word.dart';
import 'dictionary_api.dart';
import 'mapper/word_mapper.dart';
import 'model/word_response_dto.dart';

abstract interface class DictionaryRepository {
  Future<Word> lookupWord(String word);
}

final class SqliteDictionaryRepository implements DictionaryRepository {
  SqliteDictionaryRepository({required this.database, required this.api});

  final LocalDatabase database;
  final DictionaryApi api;
  final Map<String, Future<Word>> _inFlight = {};

  @override
  Future<Word> lookupWord(String word) {
    final normalized = normalizeDictionaryWord(word);
    if (normalized.isEmpty) {
      return Future.error(ArgumentError.value(word, 'word'));
    }
    return _inFlight
        .putIfAbsent(normalized, () => _lookupNormalized(normalized))
        .whenComplete(() => _inFlight.remove(normalized));
  }

  Future<Word> _lookupNormalized(String normalized) async {
    final cached = await database
        .customSelect(
          'SELECT payload_json FROM dictionary_words WHERE word = ?',
          variables: [Variable.withString(normalized)],
        )
        .getSingleOrNull();
    if (cached != null) {
      await database.customStatement(
        'UPDATE dictionary_words SET last_lookup_at_ms = ? WHERE word = ?',
        [DateTime.now().millisecondsSinceEpoch, normalized],
      );
      return WordResponseDto.fromJson(
        jsonDecode(cached.read<String>('payload_json')) as Map<String, dynamic>,
      ).toDomain();
    }

    final wordData = await api.lookupWord(normalized);
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.customStatement(
      '''INSERT INTO dictionary_words
         (word, payload_json, cached_at_ms, last_lookup_at_ms)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(word) DO UPDATE SET
           payload_json = excluded.payload_json,
           cached_at_ms = excluded.cached_at_ms,
           last_lookup_at_ms = excluded.last_lookup_at_ms''',
      [normalized, jsonEncode(wordData.toJson()), now, now],
    );
    return wordData.toDomain();
  }
}

String normalizeDictionaryWord(String value) {
  final word = value.trim().toLowerCase();
  return RegExp(r"^[a-z]+(?:['’][a-z]+)*$").hasMatch(word) ? word : '';
}
