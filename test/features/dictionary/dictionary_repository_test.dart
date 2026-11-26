import 'dart:convert';

import 'package:drift/native.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/firebase/firebase_http.dart';
import 'package:english_learning_player/features/dictionary/data/dictionary_api.dart';
import 'package:english_learning_player/features/dictionary/data/dictionary_repository.dart';
import 'package:english_learning_player/features/dictionary/data/mapper/word_mapper.dart';
import 'package:english_learning_player/features/dictionary/data/model/word_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

const wordFixture = <String, dynamic>{
  'word': 'example',
  'pronunciations': {'uk': '/ɪɡˈzɑːmpəl/', 'us': '/ɪɡˈzæmpəl/'},
  'entries': [
    {
      'part_of_speech': 'noun',
      'definitions': [
        {
          'en_definition': 'A thing characteristic of its kind.',
          'zh_definition': '例子；實例',
          'examples': [
            {'example_text': 'This is a good example.'},
          ],
        },
      ],
    },
  ],
};

void main() {
  late LocalDatabase database;
  late _FakeDictionaryApi api;
  late SqliteDictionaryRepository repository;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    api = _FakeDictionaryApi();
    repository = SqliteDictionaryRepository(database: database, api: api);
  });

  tearDown(() async => database.close());

  test('maps BlackCatNews response fields to the Word model', () {
    final response = WordResponseDto.fromJson(wordFixture);
    final word = response.toDomain();

    expect(word.word, 'example');
    expect(word.pronunciations.uk, '/ɪɡˈzɑːmpəl/');
    expect(word.entries.single.partOfSpeech, 'noun');
    expect(word.entries.single.definitions.single.zhDefinition, '例子；實例');
    expect(word.entries.single.definitions.single.examples.map((e) => e.text), [
      'This is a good example.',
    ]);
    expect(WordResponseDto.fromJson(response.toJson()).toJson(), wordFixture);
  });

  test('maps ECDICT response with a generic phonetic and no examples', () {
    final fixture = <String, dynamic>{
      'word': 'hello',
      'pronunciations': {'uk': null, 'us': null, 'phonetic': "hә'lәu"},
      'entries': [
        {
          'part_of_speech': 'interjection',
          'definitions': [
            {'en_definition': '', 'zh_definition': '喂, 嘿', 'examples': []},
          ],
        },
      ],
    };
    final response = WordResponseDto.fromJson(fixture);
    final word = response.toDomain();

    expect(word.pronunciations.uk, isNull);
    expect(word.pronunciations.us, isNull);
    expect(word.pronunciations.phonetic, "hә'lәu");
    expect(word.entries.single.definitions.single.enDefinition, isEmpty);
    expect(word.entries.single.definitions.single.zhDefinition, '喂, 嘿');
    expect(word.entries.single.definitions.single.examples, isEmpty);
    expect(WordResponseDto.fromJson(response.toJson()).toJson(), fixture);
  });

  test(
    'calls the BlackCatNews word endpoint and maps its JSON response',
    () async {
      final http = _FakeFirebaseHttp();
      final result = await BlackCatNewsDictionaryApi(http)
          .lookupWord('example');

      expect(
        http.requestedUri,
        Uri.https('dictionary.kuronekoli.uk', '/word/example'),
      );
      expect(
        result.entries.single.definitions.single.examples.single.exampleText,
        'This is a good example.',
      );
    },
  );

  test(
    'fetches a cache miss once and returns the saved word next time',
    () async {
      final first = await repository.lookupWord(' Example ');
      final second = await repository.lookupWord('EXAMPLE');

      expect(first.word, 'example');
      expect(second.entries.single.definitions.single.zhDefinition, '例子；實例');
      expect(api.calls, 1);
      final row = await database
          .customSelect('SELECT word FROM dictionary_words')
          .getSingle();
      expect(row.read<String>('word'), 'example');
    },
  );

  test('coalesces concurrent lookups for the same normalized word', () async {
    final results = await Future.wait([
      repository.lookupWord(' Example '),
      repository.lookupWord('EXAMPLE'),
    ]);

    expect(results.map((word) => word.word), ['example', 'example']);
    expect(api.calls, 1);
  });

  test(
    'refreshes pre-upgrade entries and keeps them available offline',
    () async {
      await database.customStatement(
        'INSERT INTO dictionary_words VALUES (?, ?, ?, ?)',
        ['example', jsonEncode(wordFixture), 1, 1],
      );
      api.error = const FormatException('Offline fixture');
      expect((await repository.lookupWord('example')).word, 'example');

      api.error = null;
      await repository.lookupWord('example');
      await repository.lookupWord('example');
      expect(api.calls, 2);
    },
  );

  test('propagates API failure without inserting a fake cache entry', () async {
    api.error = StateError('offline');

    await expectLater(repository.lookupWord('example'), throwsStateError);
    expect(
      await database.customSelect('SELECT word FROM dictionary_words').get(),
      isEmpty,
    );
  });

  test('rejects phrases and punctuation before calling the API', () async {
    await expectLater(repository.lookupWord('two words'), throwsArgumentError);
    await expectLater(repository.lookupWord('../word'), throwsArgumentError);
    expect(api.calls, 0);
  });
}

final class _FakeDictionaryApi implements DictionaryApi {
  int calls = 0;
  Object? error;

  @override
  Future<WordResponseDto> lookupWord(String word) async {
    calls++;
    if (error case final exception?) throw exception;
    return WordResponseDto.fromJson(wordFixture);
  }

  @override
  void close() {}
}

final class _FakeFirebaseHttp extends FirebaseHttp {
  _FakeFirebaseHttp() : super.platform();

  Uri? requestedUri;

  @override
  Future<FirebaseResponse> send(
    String method,
    Uri uri, {
    Future<String> Function()? authorization,
    String? contentType,
    Map<String, String> headers = const {},
    List<int>? bytes,
    Stream<List<int>>? body,
    int? length,
  }) async {
    expect(method, 'GET');
    requestedUri = uri;
    return FirebaseResponse(
      200,
      Stream.value(utf8.encode(jsonEncode(wordFixture))),
    );
  }

  @override
  void close() {}
}
