import 'dart:async';
import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/forecast/presenter/forecast_presenter.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';

class CashForecastScreen extends StatefulWidget {
  final ForecastPresenter presenter;
  final String currency;
  const CashForecastScreen({
    super.key,
    required this.presenter,
    required this.currency,
  });
  @override
  State<CashForecastScreen> createState() => _CashForecastScreenState();
}

class _ForecastEventInputs {
  final String kind;
  final name = TextEditingController(),
      date = TextEditingController(),
      amount = TextEditingController();
  _ForecastEventInputs(this.kind);
  void dispose() {
    name.dispose();
    date.dispose();
    amount.dispose();
  }
}

class _CashForecastScreenState extends State<CashForecastScreen>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  final daily = TextEditingController(), buffer = TextEditingController();
  final events = <_ForecastEventInputs>[];
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.presenter.invalidate();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => widget.presenter.expire(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.presenter.invalidate();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    daily.dispose();
    buffer.dispose();
    for (final event in events) {
      event.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) {
      final result = state.result;
      String amount(dynamic value) => money(value as num, widget.currency);
      Widget field(
        TextEditingController controller,
        String label, {
        bool optional = false,
        bool date = false,
        bool name = false,
        bool positive = false,
      }) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
          controller: controller,
          enabled: !state.busy,
          decoration: InputDecoration(labelText: label),
          keyboardType: name
              ? TextInputType.text
              : date
              ? TextInputType.datetime
              : const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => widget.presenter.invalidate(),
          validator: (v) => name
              ? ((v ?? '').trim().isEmpty || v!.trim().length > 80
                    ? 'Enter a name (1–80 characters)'
                    : null)
              : positive && (PlanningInputRules.amount(v ?? '') ?? 0) <= 0
              ? 'Enter a positive amount'
              : date
              ? PlanningInputRules.date(v, optional: optional)
              : PlanningInputRules.money(v, optional: optional),
        ),
      );
      return Scaffold(
        appBar: AppBar(title: const Text('30-day cash-flow forecast')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Explore projected cash, not money available to spend. Reconcile cash and review Protected Funding before calculating. Nothing here changes your records.',
            ),
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(
                    daily,
                    'Additional daily spending (${widget.currency})',
                  ),
                  const Text(
                    'Include everyday expenses beyond scheduled bills and debts. Enter 0 explicitly if none. Existing funding allowances are not also deducted.',
                  ),
                  field(buffer, 'Minimum cash buffer (${widget.currency})'),
                  const Text(
                    'Add up to 30 dated income or expense events within the next 30 days. Include only amounts not already reflected in reconciled cash, scheduled bills or daily spending.',
                  ),
                  for (final event in events)
                    Card(
                      key: ObjectKey(event),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Text(
                              event.kind == 'income'
                                  ? 'Expected income'
                                  : 'Additional expense',
                            ),
                            field(event.name, 'Event name', name: true),
                            field(
                              event.date,
                              'Event date (YYYY-MM-DD)',
                              date: true,
                            ),
                            field(
                              event.amount,
                              'Event amount (${widget.currency})',
                              positive: true,
                            ),
                            TextButton(
                              onPressed: state.busy
                                  ? null
                                  : () {
                                      setState(() => events.remove(event));
                                      widget.presenter.invalidate();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => event.dispose(),
                                          );
                                    },
                              child: const Text('Remove event'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in ['income', 'expense'])
                        OutlinedButton(
                          onPressed: state.busy || events.length >= 30
                              ? null
                              : () {
                                  setState(
                                    () =>
                                        events.add(_ForecastEventInputs(kind)),
                                  );
                                  widget.presenter.invalidate();
                                },
                          child: Text('Add $kind'),
                        ),
                    ],
                  ),
                  FilledButton(
                    onPressed: state.busy
                        ? null
                        : () {
                            if (!form.currentState!.validate()) return;
                            widget.presenter.calculate({
                              'daily_spending': PlanningInputRules.amount(
                                daily.text,
                              ),
                              'buffer': PlanningInputRules.amount(buffer.text),
                              'events': events
                                  .map(
                                    (e) => {
                                      'name': e.name.text.trim(),
                                      'date': e.date.text.trim(),
                                      'kind': e.kind,
                                      'amount': PlanningInputRules.amount(
                                        e.amount.text,
                                      ),
                                    },
                                  )
                                  .toList(),
                            });
                          },
                    child: Text(
                      state.busy ? 'Calculating…' : 'Calculate forecast',
                    ),
                  ),
                ],
              ),
            ),
            if (state.busy) const LinearProgressIndicator(),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (result.isEmpty && !state.busy)
              const Text(
                'Calculate again after changing assumptions, refreshing cash or returning to the app. Results expire after five minutes or sooner if cash expires.',
              ),
            if (result.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                '${result['as_of']} to ${result['end']} · ${result['timezone']}',
              ),
              for (final reason in result['reasons'] as List? ?? [])
                Text(reason as String),
              if (result['ready'] == true) ...[
                Text('Starting cash: ${amount(result['starting_balance'])}'),
                Text(
                  'Projected ending cash: ${amount(result['ending_balance'])}',
                ),
                Text(
                  'Lowest projected cash: ${amount(result['minimum_balance'])}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  result['first_negative'] == null
                      ? 'No projected negative balance under these assumptions.'
                      : 'First projected shortfall: ${result['first_negative']}',
                ),
                Text(
                  result['first_below_buffer'] == null
                      ? 'Projected balance stays at or above your buffer.'
                      : 'First below buffer: ${result['first_below_buffer']}',
                ),
                for (final warning in result['warnings'] as List)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(warning as String),
                  ),
                const Divider(),
                Text(
                  'Projected timeline',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final event in result['events'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${event['date']} · ${event['name']}${event['overdue'] == true ? ' · overdue' : ''}',
                    ),
                    subtitle: Text(
                      '${amount(event['amount'])} → balance ${amount(event['balance'])}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
