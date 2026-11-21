import 'account_database_opener.dart';
import 'account_database_service.dart';

Future<AccountDatabaseOpener> create() =>
    AccountDatabaseService.createForApplication();
