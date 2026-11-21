import 'account_database_opener.dart';
import 'account_database_factory_native.dart'
    if (dart.library.js_interop) 'account_database_factory_web.dart'
    as impl;

Future<AccountDatabaseOpener> createAccountDatabaseOpener() => impl.create();
