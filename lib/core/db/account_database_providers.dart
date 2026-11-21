import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_database_service.dart';
import 'account_scope.dart';

final accountScopeProvider = Provider<AccountScope>(
  (ref) => AccountScope('local-default'),
);

final accountDatabaseServiceProvider = FutureProvider<AccountDatabaseService>(
  (ref) => AccountDatabaseService.createForApplication(),
);

final localDatabaseProvider = FutureProvider.autoDispose((ref) async {
  final scope = ref.watch(accountScopeProvider);
  final storage = ref.watch(accountDatabaseServiceProvider.future);
  final service = await storage;
  final database = await service.open(scope);
  if (!ref.mounted) {
    await database.close();
    throw StateError('The selected account has changed.');
  }
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
