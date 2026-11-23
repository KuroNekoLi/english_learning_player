import 'package:material_ui/material_ui.dart';

final class TestEmailSignInDialog extends StatefulWidget {
  const TestEmailSignInDialog({super.key});

  @override
  State<TestEmailSignInDialog> createState() => _TestEmailSignInDialogState();
}

final class _TestEmailSignInDialogState extends State<TestEmailSignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('測試帳號登入'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '電子郵件'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密碼'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
          Navigator.of(context)
              .pop((email: _email.text, password: _password.text));
        },
        child: const Text('登入'),
      ),
    ],
  );
}
