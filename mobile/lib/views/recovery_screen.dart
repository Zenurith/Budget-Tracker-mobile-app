import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/recovery/presenter/recovery_presenter.dart';

class RecoveryScreen extends StatefulWidget {
  final RecoveryPresenter presenter;
  final String initialToken;
  const RecoveryScreen({
    super.key,
    required this.presenter,
    this.initialToken = '',
  });
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final email = TextEditingController(), token = TextEditingController();
  final password = TextEditingController(), confirm = TextEditingController();
  bool enteringCode = false;
  @override
  void initState() {
    super.initState();
    widget.presenter.clear();
    token.text = widget.initialToken;
    enteringCode = token.text.isNotEmpty;
  }

  @override
  void dispose() {
    for (final c in [email, token, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Recover your account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (state.reset) ...[
                const Text(
                  'Your password has been changed. Sign in with your new password. Existing sessions have been signed out.',
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to sign in'),
                ),
              ] else ...[
                const Text(
                  'Request an email, then paste its single-use reset code here. The code expires after 30 minutes.',
                ),
                const SizedBox(height: 20),
                if (!enteringCode) ...[
                  TextField(
                    controller: email,
                    enabled: !state.busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.busy
                        ? null
                        : () => widget.presenter.request(email.text),
                    child: const Text('Send reset email'),
                  ),
                  if (state.sent)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'If an account exists for that email, a reset code will be sent. Check your inbox and spam folder.',
                      ),
                    ),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => setState(() => enteringCode = true),
                    child: const Text('Enter reset code'),
                  ),
                ] else ...[
                  TextField(
                    controller: token,
                    enabled: !state.busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Reset code from email',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    enabled: !state.busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      helperText: '8–128 characters',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirm,
                    enabled: !state.busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.busy
                        ? null
                        : () => widget.presenter.reset(
                            token.text,
                            password.text,
                            confirm.text,
                          ),
                    child: const Text('Reset password'),
                  ),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => setState(() => enteringCode = false),
                    child: const Text('Request another email'),
                  ),
                ],
                if (state.busy) const LinearProgressIndicator(),
                if (state.error != null)
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
