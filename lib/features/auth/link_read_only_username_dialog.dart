import 'package:material_ui/material_ui.dart';

final class LinkReadOnlyUsernameDialog extends StatefulWidget {
  const LinkReadOnlyUsernameDialog({super.key});

  @override
  State<LinkReadOnlyUsernameDialog> createState() =>
      _LinkReadOnlyUsernameDialogState();
}

final class _LinkReadOnlyUsernameDialogState
    extends State<LinkReadOnlyUsernameDialog> {
  final _username = TextEditingController(text: 'kuroneko_li');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('設定唯讀登入帳號'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('建立獨立的唯讀登入帳號，並授權它讀取目前 Google 帳號的教材。雲端權限由伺服器控管；請輸入測試帳號密碼。'),
          TextField(
            key: const ValueKey('linkUsername'),
            controller: _username,
            autocorrect: false,
            readOnly: true,
            decoration: const InputDecoration(labelText: '帳號'),
          ),
          TextField(
            key: const ValueKey('linkPassword'),
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() => _validationError = null),
            decoration: const InputDecoration(labelText: '新密碼（至少 6 個字元）'),
          ),
          TextField(
            key: const ValueKey('linkPasswordConfirm'),
            controller: _confirm,
            obscureText: true,
            onChanged: (_) => setState(() => _validationError = null),
            decoration: const InputDecoration(labelText: '再次輸入新密碼'),
          ),
          if (_validationError case final message?) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message,
                key: const ValueKey('linkPasswordValidationError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('linkUsernameSubmit'),
        onPressed: () => _submit(context),
        child: const Text('建立唯讀帳號'),
      ),
    ],
  );

  void _submit(BuildContext context) {
    final username = _username.text.trim();
    final password = _password.text;
    final confirmation = _confirm.text;
    final error = switch (true) {
      _ when username.isEmpty => '帳號不可空白。',
      _ when password.length < 6 => '密碼至少需要 6 個字元。',
      _ when confirmation.isEmpty => '請再次輸入密碼。',
      _ when password != confirmation => '兩次輸入的密碼不一致。',
      _ => null,
    };
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    Navigator.of(context).pop((username: username, password: password));
  }
}
