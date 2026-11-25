import 'dart:convert';

import '../../../core/firebase/firebase_http.dart';
import 'model/word_response_dto.dart';

abstract interface class DictionaryApi {
  Future<WordResponseDto> lookupWord(String word);
  void close();
}

final class BlackCatNewsDictionaryApi implements DictionaryApi {
  BlackCatNewsDictionaryApi(this._http);

  final FirebaseHttp _http;

  @override
  Future<WordResponseDto> lookupWord(String word) async {
    final response = await _http.send(
      'GET',
      Uri.https('dictionary.kuronekoli.uk', '/word/$word'),
      headers: const {'Accept': 'application/json'},
    );
    await _http.requireSuccess(response);
    final body = await utf8.decoder.bind(_http.read(response)).join();
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Dictionary response must be an object.');
    }
    return WordResponseDto.fromJson(value);
  }

  @override
  void close() => _http.close();
}
