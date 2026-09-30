import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/auth/presenter/auth_presenter.dart';

class ProfileEditor extends StatefulWidget {
  final AuthPresenter presenter;
  const ProfileEditor({super.key, required this.presenter});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.presenter.state.account?.name,
  );

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) => PopScope(
      canPop: !state.busy,
      child: AlertDialog(
        title: const Text('Edit profile'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: name,
                  enabled: !state.busy,
                  autofocus: true,
                  maxLength: 80,
                  validator: widget.presenter.validateName,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.error!,
                    semanticsLabel: 'Error: ${state.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: state.busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    final saved = await widget.presenter.updateProfile(
                      name.text,
                    );
                    if (saved && context.mounted) Navigator.pop(context);
                  },
            child: Text(state.busy ? 'Saving…' : 'Save profile'),
          ),
        ],
      ),
    ),
  );
}
