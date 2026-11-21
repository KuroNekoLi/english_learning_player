import '../db/account_database_opener.dart';
import '../db/account_scope.dart';
import 'media_store.dart';
import 'media_store_factory_native.dart'
    if (dart.library.js_interop) 'media_store_factory_web.dart'
    as impl;

Future<MediaStore> createMediaStore(
  AccountDatabaseOpener opener,
  AccountScope scope,
) => impl.create(opener, scope);
