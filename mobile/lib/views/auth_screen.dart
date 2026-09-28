import 'package:flutter/material.dart';

import '../features/auth/presenter/auth_presenter.dart';
import '../core/model/contracts.dart';
import '../core/view/presenter_builder.dart';
import '../main.dart';

class AuthScreen extends StatefulWidget {
  final AuthPresenter presenter;
  const AuthScreen({super.key, required this.presenter});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool register = false, obscure = true;
  String? currency;
  bool get loading => widget.presenter.state.busy;
  String? get error => widget.presenter.state.error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit({bool demo = false}) async {
    if (!demo && !form.currentState!.validate()) return;
    await widget.presenter.authenticate(
      AuthInput(
        mode: demo
            ? 'demo'
            : register
            ? 'register'
            : 'login',
        email: email.text,
        password: password.text,
        name: name.text,
        currency: currency,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) => Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: ink,
                        foregroundColor: Color(0xFFDBEF9C),
                        child: Icon(Icons.spa_rounded),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'pocketwise',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: ink,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 42),
                  Text(
                    'A little clarity.\nA lot more possibility.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Make room for what matters.\nYour everyday money, beautifully in view.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF728077),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              register
                                  ? 'Start your fresh chapter'
                                  : 'Welcome back',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 24),
                            if (register) ...[
                              TextFormField(
                                controller: name,
                                decoration: const InputDecoration(
                                  labelText: 'Your name',
                                ),
                                validator: widget.presenter.validateName,
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                              ),
                              validator: widget.presenter.validateEmail,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: password,
                              obscureText: obscure,
                              onFieldSubmitted: (_) {
                                if (!loading) submit();
                              },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (s) => widget.presenter
                                  .validatePassword(s, register),
                            ),
                            if (register) ...[
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: currency,
                                decoration: const InputDecoration(
                                  labelText: 'Currency',
                                ),
                                validator: (value) => value == null
                                    ? "Choose your currency"
                                    : null,
                                items: InputRules.currencies
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => currency = v!,
                              ),
                            ],
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: loading ? null : submit,
                              child: Text(
                                loading
                                    ? 'One moment…'
                                    : register
                                    ? 'Create account'
                                    : 'Sign in',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: loading
                                  ? null
                                  : () => setState(() {
                                      register = !register;
                                      widget.presenter.clearError();
                                    }),
                              child: Text(
                                register
                                    ? 'Already have an account? Sign in'
                                    : 'New here? Create an account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: loading ? null : () => submit(demo: true),
                    icon: const Icon(Icons.explore_outlined),
                    label: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Take a look around · Try the demo'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Demo uses sample data in local development.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF728077), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
