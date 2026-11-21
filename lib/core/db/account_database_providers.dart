import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_database_opener.dart';
import 'account_database_factory.dart';
import 'account_scope.dart';

final accountScopeProvider = Provider<AccountScope>(
  (ref) => AccountScope('local-default'),
);

final accountDatabaseServiceProvider = FutureProvider<AccountDatabaseOpener>(
  (ref) => createAccountDatabaseOpener(),
);

final localDatabaseProvider = FutureProvider.autoDispose((ref) async {
  final scope = ref.watch(accountScopeProvider);
  final storage = ref.watch(accountDatabaseServiceProvider.future);
  final service = await storage;
  final database = await service.openDatabase(scope);
  if (!ref.mounted) {
    await database.close();
    throw StateError('The selected account has changed.');
  }
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
