import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/notifications/model/notification_repository.dart';
import '../features/notifications/presenter/notification_presenter.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final NotificationPresenter presenter;
  const NotificationSettingsScreen({super.key, required this.presenter});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  NotificationPresenter get p => widget.presenter;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    p.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) p.refreshPermission();
  }

  String permissionText(NotificationPermission permission) =>
      switch (permission) {
        NotificationPermission.unknown => 'Permission status unavailable',
        NotificationPermission.notDetermined => 'Permission not requested',
        NotificationPermission.denied => 'Permission not allowed',
        NotificationPermission.blocked =>
          'Notifications blocked in system settings',
        NotificationPermission.granted => 'Device permission allowed',
        NotificationPermission.provisional =>
          'Quiet delivery allowed by your device',
        NotificationPermission.unsupported =>
          'Device notifications are available in the Android and iOS apps',
      };

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: p,
    builder: (context, state) {
      final preferences = state.preferences;
      final supported = state.permission != NotificationPermission.unsupported;
      final editable = state.loaded && !state.saving && supported;
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'These preferences apply to Pocketwise on this device, across sign-ins. They are not synced to your other devices.',
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Reminder delivery is coming soon. You can save your preferences and manage device permission now.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Device permission',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(permissionText(state.permission)),
            if (state.checking)
              const LinearProgressIndicator(
                semanticsLabel: 'Checking notification permission',
              ),
            if (state.permissionError != null) Text(state.permissionError!),
            const SizedBox(height: 8),
            if (supported) ...[
              const Text(
                'Allow access to receive the reminders you choose. You can change access in system settings at any time.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if ([
                    NotificationPermission.notDetermined,
                    NotificationPermission.denied,
                  ].contains(state.permission))
                    FilledButton(
                      onPressed: state.checking ? null : p.requestPermission,
                      child: const Text('Allow notifications'),
                    ),
                  OutlinedButton(
                    onPressed: state.checking ? null : p.openSettings,
                    child: const Text('Open system settings'),
                  ),
                  TextButton(
                    onPressed: state.checking ? null : p.refreshPermission,
                    child: const Text('Refresh permission'),
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            Text(
              'Your preferences',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (state.saving)
              const LinearProgressIndicator(
                semanticsLabel: 'Saving notification preferences',
              ),
            if (!state.loaded && state.error == null)
              const LinearProgressIndicator(),
            if (state.error != null) ...[
              Text(state.error!),
              if (!state.loaded)
                TextButton(
                  onPressed: p.load,
                  child: const Text('Retry preferences'),
                ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use notifications'),
              subtitle: const Text(
                'Turning this off keeps your choices below and does not change device permission.',
              ),
              value: preferences.enabled,
              onChanged: editable
                  ? (v) => p.save(preferences.copy(enabled: v))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bill reminders'),
              subtitle: const Text(
                'Remind me about upcoming bills and debt payments.',
              ),
              value: preferences.bills,
              onChanged: editable && preferences.enabled
                  ? (v) => p.save(preferences.copy(bills: v))
                  : null,
            ),
            DropdownButtonFormField<int>(
              key: ValueKey(preferences.billLeadDays),
              initialValue: preferences.billLeadDays,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Remind me'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('On the due date')),
                DropdownMenuItem(value: 1, child: Text('1 day before')),
                DropdownMenuItem(value: 3, child: Text('3 days before')),
                DropdownMenuItem(value: 7, child: Text('7 days before')),
              ],
              onChanged: editable && preferences.enabled && preferences.bills
                  ? (v) {
                      if (v != null) p.save(preferences.copy(billLeadDays: v));
                    }
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Budget alerts'),
              subtitle: const Text(
                'Use the alert thresholds set on your budgets.',
              ),
              value: preferences.budgets,
              onChanged: editable && preferences.enabled
                  ? (v) => p.save(preferences.copy(budgets: v))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cash review reminders'),
              subtitle: const Text(
                'Remind me when my confirmed cash and funding plan need review.',
              ),
              value: preferences.cashReview,
              onChanged: editable && preferences.enabled
                  ? (v) => p.save(preferences.copy(cashReview: v))
                  : null,
            ),
            const Text(
              'Changes save automatically. Your in-app budget alerts remain available regardless of these device notification preferences.',
            ),
          ],
        ),
      );
    },
  );
}
