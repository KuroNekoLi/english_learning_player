import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import 'bookmark_repository.dart';
import 'data/sqlite_bookmark_repository.dart';

final bookmarkRepositoryProvider = FutureProvider<BookmarkRepository>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  final database = await ref.watch(localDatabaseProvider.future);
  return SqliteBookmarkRepository(scope: scope, database: database);
});
