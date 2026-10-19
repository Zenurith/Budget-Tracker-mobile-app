import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../features/planning/presenter/planning_presenter.dart';
import '../models/finance.dart';

/// A month view of server-calculated obligations, using the profile's local date.
class PlanningCalendar extends StatefulWidget {
  final PlanningState state;
  final Widget Function(Json) occurrenceBuilder;
  const PlanningCalendar({
    super.key,
    required this.state,
    required this.occurrenceBuilder,
  });

  @override
  State<PlanningCalendar> createState() => _PlanningCalendarState();
}

class _PlanningCalendarState extends State<PlanningCalendar> {
  String? selected;

  @override
  void didUpdateWidget(PlanningCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.month != widget.state.month) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final month = state.month;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = DateTime(month.year, month.month).weekday - 1;
    final items = state.items('occurrences');
    final payday = state.data['next_income_date'] as String?;
    final today = state.data['as_of'] as String?;
    final visiblePayday =
        payday != null &&
        payday.startsWith(DateFormat('yyyy-MM').format(month));
    final overdue = items.where((e) => e['overdue'] == true).length;
    final shown = items.where(
      (e) => selected == null || e['due_date'] == selected,
    );
    final colors = Theme.of(context).colorScheme;
    final enabled = !state.busy && !state.saving && state.error == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Payment calendar', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '$overdue overdue in this month',
          style: TextStyle(color: overdue > 0 ? colors.error : null),
        ),
        const Text(
          'Dots mark obligations. An income icon marks your confirmed next payday. Select a day to see details.',
        ),
        if (!visiblePayday)
          const Text(
            'No confirmed payday in this month. Set the next income date in Protected Funding.',
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        for (var week = 0; week < (offset + days + 6) ~/ 7; week++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = week * 7 + column - offset + 1;
                      if (day < 1 || day > days) {
                        return const SizedBox(height: 64);
                      }
                      final date = dateOf(
                        DateTime(month.year, month.month, day),
                      );
                      final due = items
                          .where((e) => e['due_date'] == date)
                          .toList();
                      final late = due.any((e) => e['overdue'] == true);
                      final income = date == payday;
                      return Semantics(
                        label:
                            '$date, ${due.length} obligations${late ? ', overdue' : ''}${income ? ', expected income' : ''}${date == today ? ', today' : ''}',
                        selected: date == selected,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Material(
                            color: date == selected
                                ? colors.primaryContainer
                                : date == today
                                ? colors.surfaceContainerHighest
                                : colors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: late
                                    ? colors.error
                                    : colors.outlineVariant,
                              ),
                            ),
                            child: InkWell(
                              onTap: enabled
                                  ? () => setState(
                                      () => selected = date == selected
                                          ? null
                                          : date,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 60,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('$day'),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        if (due.isNotEmpty)
                                          Icon(
                                            Icons.circle,
                                            size: 10,
                                            color: late
                                                ? colors.error
                                                : colors.primary,
                                          ),
                                        if (income)
                                          Icon(
                                            Icons.south_west,
                                            size: 14,
                                            color: colors.primary,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        if (selected != null)
          TextButton(
            onPressed: () => setState(() => selected = null),
            child: const Text('Show whole month'),
          ),
        Text(
          selected == null ? 'This month’s agenda' : 'Agenda · $selected',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (visiblePayday && (selected == null || selected == payday))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$payday · Expected income\nConfirmed next payday. This does not record income or add available cash.',
              ),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              selected == null
                  ? 'No scheduled obligations in this month.'
                  : 'No scheduled obligations on this day.',
            ),
          ),
        for (final due in shown) widget.occurrenceBuilder(due),
      ],
    );
  }
}
