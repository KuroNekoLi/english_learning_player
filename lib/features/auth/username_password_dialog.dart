import 'package:material_ui/material_ui.dart';

final class UsernamePasswordDialog extends StatefulWidget {
  const UsernamePasswordDialog({super.key});

  @override
  State<UsernamePasswordDialog> createState() => _UsernamePasswordDialogState();
}

final class _UsernamePasswordDialogState extends State<UsernamePasswordDialog> {
  final _username = TextEditingController(text: 'kuroneko_li');
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('帳號密碼登入（唯讀）'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('usernameLoginUsername'),
          controller: _username,
          readOnly: true,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '帳號'),
        ),
        TextField(
          key: const ValueKey('usernameLoginPassword'),
          controller: _password,
          obscureText: true,
          onSubmitted: (_) => _submit(context),
          decoration: const InputDecoration(labelText: '密碼'),
        ),
        const SizedBox(height: 8),
        const Text('此登入方式只能讀取和下載雲端教材，不能上傳、修改或刪除雲端資料。'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('usernameLoginSubmit'),
        onPressed: () => _submit(context),
        child: const Text('登入'),
      ),
    ],
  );

  void _submit(BuildContext context) {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    Navigator.of(context).pop((username: username, password: password));
  }
}
