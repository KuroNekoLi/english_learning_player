import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/audio/audio_engine_provider.dart';
import '../../core/audio/speech_playback.dart';
import '../../core/firebase/firebase_http.dart';
import '../library/library_dependencies.dart';
import '../player/player_dependencies.dart';
import '../player/player_view_model.dart';
import 'data/dictionary_api.dart';
import 'data/dictionary_repository.dart';
import 'data/original_context_playback.dart';
import 'data/word_bank_repository.dart';
import 'domain/word.dart';
import 'domain/original_word_context.dart';
import 'domain/saved_dictionary_word.dart';

final wordBankRepositoryProvider =
    FutureProvider.autoDispose<WordBankRepository>(
      (ref) async =>
          WordBankRepository(await ref.watch(localDatabaseProvider.future)),
      retry: (_, _) => null,
    );

final savedDictionaryWordsProvider =
    FutureProvider.autoDispose<List<SavedDictionaryWord>>(
      (ref) async =>
          (await ref.watch(wordBankRepositoryProvider.future)).list(),
      retry: (_, _) => null,
    );

final canEditWordBankProvider = Provider<bool>((ref) {
  final account = ref.watch(accountScopeProvider);
  return account.ownerId == account.cloudUid;
});

final updateSavedDictionaryWordProvider =
    Provider<
      Future<void> Function(
        Word, {
        required bool save,
        OriginalWordContext? context,
      })
    >((ref) {
      return (word, {required save, context}) async {
        if (!ref.read(canEditWordBankProvider)) {
          throw StateError('The word bank is read-only for this account.');
        }
        final repository = await ref.read(wordBankRepositoryProvider.future);
        if (save) {
          await repository.save(word, context: context);
        } else if (context != null) {
          await repository.attachContext(word.word, context);
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

final originalContextPlaybackProvider = FutureProvider<OriginalContextPlayback>(
  (ref) async {
    final audio = ref.watch(audioEngineProvider);
    final scope = ref.watch(accountScopeProvider);
    final materials = await ref.watch(materialRepositoryProvider.future);
    final loader = await ref.watch(materialPlaybackLoaderProvider.future);
    final playback = OriginalContextPlayback(
      audio,
      materials,
      loader,
      scope,
      ref.watch(speechPlaybackProvider),
      () => ref
          .read(playerViewModelProvider.notifier)
          .suspendForOriginalContext(),
      (resume) => ref
          .read(playerViewModelProvider.notifier)
          .resumeAfterOriginalContext(resume),
    );
    ref.onDispose(() => unawaited(playback.dispose()));
    return playback;
  },
  retry: (_, _) => null,
);
