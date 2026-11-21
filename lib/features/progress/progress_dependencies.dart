import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import 'data/progress_repository.dart';
import 'data/sqlite_progress_repository.dart';

final progressRepositoryProvider = FutureProvider<ProgressRepository>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  final database = await ref.watch(localDatabaseProvider.future);
  return SqliteProgressRepository(scope: scope, db: database);
});
