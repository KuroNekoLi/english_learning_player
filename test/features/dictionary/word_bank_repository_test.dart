import 'dart:io';

import 'package:drift/native.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/features/dictionary/data/word_bank_repository.dart';
import 'package:english_learning_player/features/dictionary/domain/word.dart';
import 'package:english_learning_player/features/dictionary/domain/original_word_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'upgrading v11 preserves saved words without replaying old removals',
    () async {
      final directory = await Directory.systemTemp.createTemp('word-bank-v11');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/words.sqlite');
      final old = LocalDatabase(NativeDatabase(file));
      await WordBankRepository(old).save(_refine);
      await old.customStatement('''
      CREATE TABLE old_saved_words (
        word TEXT PRIMARY KEY, payload_json TEXT NOT NULL, saved_at_ms INTEGER NOT NULL
      )
    ''');
      await old.customStatement(
        'INSERT INTO old_saved_words SELECT word, payload_json, saved_at_ms FROM dictionary_saved_words',
      );
      await old.customStatement('DROP TABLE dictionary_saved_words');
      await old.customStatement(
        'ALTER TABLE old_saved_words RENAME TO dictionary_saved_words',
      );
      await old.customStatement('PRAGMA user_version = 11');
      await old.close();

      final db = LocalDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final bank = WordBankRepository(db);
      final entry = (await bank.pending()).single;
      expect(entry.migrated, isTrue);
      expect(entry.change.opId, matches(r'^[0-9a-f]{32}$'));
      expect((await bank.list()).single.word.word, 'refine');
      await bank.merge([
        (
          word: 'refine',
          payload: '',
          savedAtMs: 100,
          revision: 2,
          opId: 'remote',
        ),
      ]);
      expect(await bank.list(), isEmpty);
      expect(await bank.pending(), isEmpty);
    },
  );
  test(
    'v10 upgrades without clearing lookup cache or sharing favorites',
    () async {
      final directory = await Directory.systemTemp.createTemp('word-bank-test');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/owner-a.sqlite');
      final old = LocalDatabase(NativeDatabase(file));
      await old.customStatement('DROP TABLE dictionary_saved_words');
      await old.customStatement(
        "INSERT INTO dictionary_words VALUES ('refine', '{}', 100, 100)",
      );
      await old.customStatement('PRAGMA user_version = 10');
      await old.close();

      final first = LocalDatabase(NativeDatabase(file));
      final firstBank = WordBankRepository(first);
      expect(await firstBank.list(), isEmpty);
      expect(
        (await first
                .customSelect('SELECT word FROM dictionary_words')
                .getSingle())
            .read<String>('word'),
        'refine',
      );
      await firstBank.save(_refine);
      await firstBank.save(_refine);
      await first.close();

      final second = LocalDatabase(
        NativeDatabase(File('${directory.path}/owner-b.sqlite')),
      );
      try {
        expect(await WordBankRepository(second).list(), isEmpty);
      } finally {
        await second.close();
      }
      final reopened = LocalDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      final bank = WordBankRepository(reopened);
      final saved = (await bank.list()).single;
      expect(saved.word.word, 'refine');
      expect(saved.word.pronunciations.phonetic, '/rɪˈfaɪn/');
      expect(
        saved.word.entries.single.definitions.single.examples.single.text,
        'The factory refines sugar.\n工廠提煉砂糖。',
      );
      await bank.remove(' REFINE ');
      expect(await bank.list(), isEmpty);
      expect(
        await reopened.customSelect('SELECT word FROM dictionary_words').get(),
        hasLength(1),
      );
    },
  );

  test(
    'saves the first original context and attaches old entries in place',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final bank = WordBankRepository(db);
      const first = OriginalWordContext(
        materialId: 'lesson-1',
        materialTitle: 'Lesson one',
        startMs: 45000,
        endMs: 48000,
        english: 'It is incredibly murky.',
        translations: ['非常模糊。'],
      );
      const second = OriginalWordContext(
        materialId: 'lesson-2',
        materialTitle: 'Lesson two',
        startMs: 8000,
        endMs: 12000,
        english: 'The water looks murky.',
        translations: [],
      );

      await bank.save(_refine);
      final savedAtBeforeAttach =
          (await bank.pending()).single.change.savedAtMs;
      expect(await bank.attachContext('refine', first), isTrue);
      final attached = (await bank.list()).single;
      expect(attached.originalContext?.materialId, 'lesson-1');
      expect(
        attached.word.entries.single.definitions.single.zhDefinition,
        '提煉。',
      );
      final savedAtAfterAttach = (await bank.pending()).single.change.savedAtMs;
      expect(savedAtAfterAttach, savedAtBeforeAttach);

      await bank.save(_refine, context: second);
      expect(
        (await bank.list()).single.originalContext?.materialId,
        'lesson-1',
      );
      expect(await bank.attachContext('refine', second), isFalse);
      expect(
        (await bank.pending()).single.change.payload,
        contains('original_context'),
      );
    },
  );
}

const _refine = Word(
  word: 'refine',
  pronunciations: WordPronunciations(phonetic: '/rɪˈfaɪn/'),
  entries: [
    WordEntry(
      partOfSpeech: 'verb',
      definitions: [
        WordDefinition(
          enDefinition: 'To remove impurities.',
          zhDefinition: '提煉。',
          examples: [WordExample(text: 'The factory refines sugar.\n工廠提煉砂糖。')],
        ),
      ],
    ),
  ],
);
