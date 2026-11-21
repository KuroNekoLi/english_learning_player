import 'account_database_opener.dart';
import 'web_account_database_service.dart';

Future<AccountDatabaseOpener> create() async =>
    const WebAccountDatabaseService();
