import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/firebase/firebase_http.dart';
import 'data/dictionary_api.dart';
import 'data/dictionary_repository.dart';
import 'data/word_bank_repository.dart';
import 'domain/word.dart';

final wordBankRepositoryProvider =
    FutureProvider.autoDispose<WordBankRepository>(
      (ref) async =>
          WordBankRepository(await ref.watch(localDatabaseProvider.future)),
      retry: (_, _) => null,
    );

final savedDictionaryWordsProvider = FutureProvider.autoDispose<List<Word>>(
  (ref) async => (await ref.watch(wordBankRepositoryProvider.future)).list(),
  retry: (_, _) => null,
);

final canEditWordBankProvider = Provider<bool>((ref) {
  final account = ref.watch(accountScopeProvider);
  return account.ownerId == account.cloudUid;
});

final updateSavedDictionaryWordProvider =
    Provider<Future<void> Function(Word, {required bool save})>((ref) {
      return (word, {required save}) async {
        if (!ref.read(canEditWordBankProvider)) {
          throw StateError('The word bank is read-only for this account.');
        }
        final repository = await ref.read(wordBankRepositoryProvider.future);
        if (save) {
          await repository.save(word);
        } else {
          await repository.remove(word.word);
        }
        if (ref.mounted) ref.invalidate(savedDictionaryWordsProvider);
      };
    });

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
