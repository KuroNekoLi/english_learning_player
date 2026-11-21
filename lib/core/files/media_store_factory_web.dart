import '../db/account_database_opener.dart';
import '../db/account_scope.dart';
import 'media_store.dart';
import 'web_media_store.dart';

Future<MediaStore> create(
  AccountDatabaseOpener opener,
  AccountScope scope,
) async => WebMediaStore(scope);
