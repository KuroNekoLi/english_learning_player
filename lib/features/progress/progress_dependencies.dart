import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import 'data/progress_repository.dart';
import 'data/sqlite_progress_repository.dart';

final progressRepositoryProvider = FutureProvider<ProgressRepository>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  final database = await ref.watch(localDatabaseProvider.future);
  return SqliteProgressRepository(scope: scope, db: database);
});
