import '../db/account_database_opener.dart';
import '../db/account_database_service.dart';
import '../db/account_scope.dart';
import 'app_media_store.dart';
import 'media_store.dart';

Future<MediaStore> create(
  AccountDatabaseOpener opener,
  AccountScope scope,
) async {
  if (opener is! AccountDatabaseService) {
    throw StateError('Native media storage requires AccountDatabaseService.');
  }
  return AppMediaStore(storage: opener, scope: scope);
}
