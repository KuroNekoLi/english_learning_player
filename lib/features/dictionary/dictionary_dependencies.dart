import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/firebase/firebase_http.dart';
import 'data/dictionary_api.dart';
import 'data/dictionary_repository.dart';

final dictionaryRepositoryProvider = FutureProvider<DictionaryRepository>((
  ref,
) async {
  final api = BlackCatNewsDictionaryApi(FirebaseHttp());
  ref.onDispose(api.close);
  return SqliteDictionaryRepository(
    database: await ref.watch(localDatabaseProvider.future),
    api: api,
  );
}, retry: (_, _) => null);
