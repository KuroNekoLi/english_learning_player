import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/db/local_database.dart';

typedef SyncPreferenceKey = ({String uid, String project});

enum SyncPreference { undecided, enabled, disabled }

final syncPreferenceProvider = AsyncNotifierProvider.autoDispose
    .family<SyncPreferenceController, SyncPreference, SyncPreferenceKey>(
      SyncPreferenceController.new,
    );

final syncPreferenceStoreProvider =
    FutureProvider.autoDispose<SyncPreferencePersistence>((ref) async {
      return SyncPreferenceStore(await ref.watch(localDatabaseProvider.future));
    });

abstract interface class SyncPreferencePersistence {
  Future<SyncPreference> read(SyncPreferenceKey key);
  Future<void> write(SyncPreferenceKey key, SyncPreference choice);
}

final class SyncPreferenceController extends AsyncNotifier<SyncPreference> {
  SyncPreferenceController(this.key);

  final SyncPreferenceKey key;

  @override
  Future<SyncPreference> build() async {
    final store = await _watchStore();
    return store.read(key);
  }

  Future<void> choose(SyncPreference choice) async {
    if (state.isLoading || choice == SyncPreference.undecided) return;
    state = const AsyncLoading();
    final saved = await AsyncValue.guard(() async {
      final store = await _readStore();
      await store.write(key, choice);
      return choice;
    });
    if (ref.mounted) state = saved;
  }

  Future<SyncPreferencePersistence> _watchStore() async {
    _checkScope(ref.watch(accountScopeProvider).ownerId);
    return ref.watch(syncPreferenceStoreProvider.future);
  }

  Future<SyncPreferencePersistence> _readStore() async {
    _checkScope(ref.read(accountScopeProvider).ownerId);
    return ref.read(syncPreferenceStoreProvider.future);
  }

  void _checkScope(String ownerId) {
    if (ownerId != key.uid) throw StateError('Sync preference owner mismatch.');
  }
}

final class SyncPreferenceStore implements SyncPreferencePersistence {
  const SyncPreferenceStore(this._database);

  final LocalDatabase _database;

  @override
  Future<SyncPreference> read(SyncPreferenceKey key) async {
    final row = await _database
        .customSelect(
          'SELECT enabled FROM sync_preferences WHERE owner_id = ? AND project_id = ?',
          variables: [
            Variable.withString(key.uid),
            Variable.withString(key.project),
          ],
        )
        .getSingleOrNull();
    if (row == null) return SyncPreference.undecided;
    return row.read<int>('enabled') == 1
        ? SyncPreference.enabled
        : SyncPreference.disabled;
  }

  @override
  Future<void> write(SyncPreferenceKey key, SyncPreference choice) {
    if (choice == SyncPreference.undecided) throw ArgumentError.value(choice);
    return _database.customStatement(
      '''INSERT INTO sync_preferences (owner_id, project_id, enabled)
         VALUES (?, ?, ?)
         ON CONFLICT(owner_id, project_id) DO UPDATE SET enabled = excluded.enabled''',
      [key.uid, key.project, choice == SyncPreference.enabled ? 1 : 0],
    );
  }
}
