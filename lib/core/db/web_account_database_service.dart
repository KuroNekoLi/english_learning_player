import 'package:drift/wasm.dart';

import 'account_database_opener.dart';
import 'account_scope.dart';
import 'local_database.dart';
import 'web_storage_policy.dart';

/// Opens the shared Drift schema using browser-managed persistent storage.
///
/// Callers must check [WebAccountDatabase.storageIsSafeForWrites] before
/// writing. Drift can fall back to modes without cross-tab coordination.
final class WebAccountDatabaseService implements AccountDatabaseOpener {
  const WebAccountDatabaseService();

  Future<WebAccountDatabase> open(AccountScope scope) async {
    final name = 'english_learning_player_${scope.storageKey}';
    final result = await WasmDatabase.open(
      databaseName: name,
      sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
      driftWorkerUri: Uri.base.resolve('drift_worker.dart.js'),
    );

    return WebAccountDatabase(
      database: LocalDatabase(result.resolvedExecutor),
      databaseName: name,
      chosenImplementation: result.chosenImplementation,
      missingFeatures: result.missingFeatures,
    );
  }

  @override
  Future<LocalDatabase> openDatabase(AccountScope scope) async {
    final result = await open(scope);
    if (!result.storageIsSafeForWrites) {
      await result.database.close();
      throw StateError(
        'Browser storage mode ${result.chosenImplementation.name} is not '
        'safe for persistent writes.',
      );
    }
    return result.database;
  }
}

final class WebAccountDatabase {
  const WebAccountDatabase({
    required this.database,
    required this.databaseName,
    required this.chosenImplementation,
    required this.missingFeatures,
  });

  final LocalDatabase database;
  final String databaseName;
  final WasmStorageImplementation chosenImplementation;
  final Set<MissingBrowserFeature> missingFeatures;

  bool get storageIsSafeForWrites =>
      webStorageModeAllowsWrites(chosenImplementation.name);
}
