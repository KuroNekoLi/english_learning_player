import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import 'bookmark_repository.dart';
import 'data/sqlite_bookmark_repository.dart';

final bookmarkRepositoryProvider = FutureProvider<BookmarkRepository>((
  ref,
) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return SqliteBookmarkRepository(
    scope: ref.watch(accountScopeProvider),
    database: database,
  );
});
