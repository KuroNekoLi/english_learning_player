import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/local_database.dart';
import '../domain/word.dart';
import 'dictionary_repository.dart';
import 'mapper/word_mapper.dart';
import 'model/word_response_dto.dart';

typedef WordBankChange = ({
  String word,
  String payload,
  int savedAtMs,
  int revision,
  String opId,
});

final class WordBankRepository {
  const WordBankRepository(this._database);

  final LocalDatabase _database;

  Future<List<Word>> list() async {
    final rows = await _database.customSelect('''
      SELECT payload_json FROM dictionary_saved_words WHERE payload_json != ''
      ORDER BY saved_at_ms DESC, word ASC
    ''').get();
    return [
      for (final row in rows) decodeSavedWord(row.read<String>('payload_json')),
    ];
  }

  Future<void> save(Word word) =>
      _edit(word.word, jsonEncode(word.toDto().toJson()));

  Future<void> remove(String word) => _edit(word, '');

  Future<void> _edit(String word, String payload) {
    final key = normalizeDictionaryWord(word);
    if (key.isEmpty || key.length > 128) {
      throw ArgumentError.value(word, 'word');
    }
    if (utf8.encode(payload).length > 500000) {
      throw const FormatException('Word bank entry is too large');
    }
    return _database.customStatement(
      '''
      INSERT INTO dictionary_saved_words (word, payload_json, saved_at_ms, pending, op_id)
      VALUES (?, ?, ?, 1, lower(hex(randomblob(16))))
      ON CONFLICT(word) DO UPDATE SET payload_json = excluded.payload_json,
        saved_at_ms = excluded.saved_at_ms, pending = 1, op_id = excluded.op_id
      ''',
      [key, payload, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<List<({WordBankChange change, bool migrated})>> pending() async {
    final rows = await _database.customSelect('''
      SELECT * FROM dictionary_saved_words WHERE pending != 0
      ORDER BY saved_at_ms, word LIMIT 20
    ''').get();
    return [
      for (final row in rows)
        (
          change: (
            word: row.read<String>('word'),
            payload: row.read<String>('payload_json'),
            savedAtMs: row.read<int>('saved_at_ms'),
            revision: row.read<int>('revision'),
            opId: row.read<String>('op_id'),
          ),
          migrated: row.read<int>('pending') == 2,
        ),
    ];
  }

  Future<void> acknowledge(WordBankChange change, int revision) =>
      _database.customStatement(
        '''
        UPDATE dictionary_saved_words SET revision = max(revision, ?),
          pending = CASE WHEN op_id = ? THEN 0 ELSE pending END
        WHERE word = ?
        ''',
        [revision, change.opId, change.word],
      );

  Future<void> acceptConflict(WordBankChange local, WordBankChange remote) =>
      _database.customStatement(
        '''
        UPDATE dictionary_saved_words
        SET revision = ?, pending = 0, op_id = ?, payload_json = ?, saved_at_ms = ?
        WHERE word = ? AND op_id = ?
        ''',
        [
          remote.revision,
          remote.opId,
          remote.payload,
          remote.savedAtMs,
          local.word,
          local.opId,
        ],
      );

  /// A user edit waiting for upload wins over a pull. A v11 import only
  /// fills missing remote words, so a previous remote removal survives upgrade.
  Future<bool> merge(Iterable<WordBankChange> changes) =>
      _database.transaction(() async {
        var updated = false;
        for (final change in changes) {
          final count = await _database.customUpdate(
            '''
            INSERT INTO dictionary_saved_words
              (word, payload_json, saved_at_ms, revision, pending, op_id)
            VALUES (?, ?, ?, ?, 0, ?)
            ON CONFLICT(word) DO UPDATE SET payload_json = excluded.payload_json,
              saved_at_ms = excluded.saved_at_ms, revision = excluded.revision,
              pending = 0, op_id = excluded.op_id
            WHERE dictionary_saved_words.pending != 1
              AND dictionary_saved_words.revision < excluded.revision
            ''',
            variables: [
              Variable.withString(change.word),
              Variable.withString(change.payload),
              Variable.withInt(change.savedAtMs),
              Variable.withInt(change.revision),
              Variable.withString(change.opId),
            ],
          );
          updated = updated || count > 0;
        }
        return updated;
      });
}

Word decodeSavedWord(String payload) =>
    WordResponseDto.fromJson(jsonDecode(payload) as Map<String, dynamic>)
        .toDomain();
