import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/local_database.dart';
import '../domain/word.dart';
import '../domain/original_word_context.dart';
import '../domain/saved_dictionary_word.dart';
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

  Future<List<SavedDictionaryWord>> list() async {
    final rows = await _database.customSelect('''
      SELECT payload_json FROM dictionary_saved_words WHERE payload_json != ''
      ORDER BY saved_at_ms DESC, word ASC
    ''').get();
    return [
      for (final row in rows)
        decodeSavedEntry(row.read<String>('payload_json')),
    ];
  }

  Future<void> save(Word word, {OriginalWordContext? context}) =>
      _database.transaction(() async {
        final key = normalizeDictionaryWord(word.word);
        if (key.isEmpty || key.length > 128) {
          throw ArgumentError.value(word.word, 'word');
        }
        final existing = await _database
            .customSelect(
              'SELECT payload_json FROM dictionary_saved_words WHERE word = ?',
              variables: [Variable.withString(key)],
            )
            .getSingleOrNull();
        final existingPayload = existing?.read<String>('payload_json');
        final oldContext = existingPayload == null || existingPayload.isEmpty
            ? null
            : decodeSavedEntry(existingPayload).originalContext;
        final payload = _payload(word, oldContext ?? context);
        _validatePayload(payload);
        await _database.customStatement(
          '''
          INSERT INTO dictionary_saved_words (word, payload_json, saved_at_ms, pending, op_id)
          VALUES (?, ?, ?, 1, lower(hex(randomblob(16))))
          ON CONFLICT(word) DO UPDATE SET payload_json = excluded.payload_json,
            saved_at_ms = excluded.saved_at_ms, pending = 1, op_id = excluded.op_id
          ''',
          [key, payload, DateTime.now().millisecondsSinceEpoch],
        );
      });

  /// Attaches the first available context to an existing saved word without
  /// changing its dictionary snapshot or its original saved ordering.
  Future<bool> attachContext(String word, OriginalWordContext context) async {
    final key = normalizeDictionaryWord(word);
    if (key.isEmpty ||
        !context.isPlayableRange ||
        context.english.trim().isEmpty) {
      return false;
    }
    return _database.transaction(() async {
      final row = await _database
          .customSelect(
            'SELECT payload_json, saved_at_ms FROM dictionary_saved_words WHERE word = ? AND payload_json != ?',
            variables: [Variable.withString(key), Variable.withString('')],
          )
          .getSingleOrNull();
      if (row == null) return false;
      final payload = row.read<String>('payload_json');
      final saved = decodeSavedEntry(payload);
      if (saved.originalContext != null) return false;
      final updated = _payload(saved.word, context);
      _validatePayload(updated);
      await _database.customStatement(
        '''
        UPDATE dictionary_saved_words
        SET payload_json = ?, pending = 1, op_id = lower(hex(randomblob(16)))
        WHERE word = ? AND payload_json = ? AND payload_json != ''
        ''',
        [updated, key, payload],
      );
      return true;
    });
  }

  Future<void> remove(String word) => _edit(word, '');

  Future<void> _edit(String word, String payload) {
    final key = normalizeDictionaryWord(word);
    if (key.isEmpty || key.length > 128) {
      throw ArgumentError.value(word, 'word');
    }
    _validatePayload(payload);
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

String _payload(Word word, OriginalWordContext? context) => jsonEncode({
  ...word.toDto().toJson(),
  if (context != null) 'original_context': context.toJson(),
});

void _validatePayload(String payload) {
  if (utf8.encode(payload).length > 500000) {
    throw const FormatException('Word bank entry is too large');
  }
}

SavedDictionaryWord decodeSavedEntry(String payload) {
  final json = jsonDecode(payload) as Map<String, dynamic>;
  return SavedDictionaryWord(
    word: WordResponseDto.fromJson(json).toDomain(),
    originalContext: OriginalWordContext.tryParse(json['original_context']),
  );
}

Word decodeSavedWord(String payload) => decodeSavedEntry(payload).word;
