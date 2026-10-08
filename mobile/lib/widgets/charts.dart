import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/overview/presenter/overview_presenter.dart';
import '../core/view/category_style.dart';
import '../main.dart';
import '../models/finance.dart';

class SpendingChart extends StatelessWidget {
  final OverviewPresenter presenter;
  const SpendingChart({super.key, required this.presenter});
  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(17) > 23;
    final values =
        (presenter.summary['category_breakdown'] as Json? ?? {}).entries
            .toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final total = values.fold<int>(0, (sum, e) => sum + (e.value as int));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where it went', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'A little perspective on your spending',
          style: TextStyle(color: mutedInk),
        ),
        const SizedBox(height: 24),
        if (total == 0)
          const SizedBox(
            height: 190,
            child: Center(child: Text('Add an expense to see your breakdown.')),
          )
        else
          LayoutBuilder(
            builder: (context, size) {
              final ring = Semantics(
                label:
                    'Total recorded spending: ${money(total, presenter.currency)}',
                excludeSemantics: true,
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: RingPainter(
                            values
                                .map(
                                  (e) => (
                                    value: (e.value as num).toDouble(),
                                    color: presenter.category(e.key).color,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      if (!largeText)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SPENT',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.5,
                                color: mutedInk,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              money(total, presenter.currency),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
              final legend = Column(
                children: values
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Semantics(
                          label:
                              '${presenter.category(e.key).name}: ${money(e.value, presenter.currency)}, ${(e.value / total * 100).round()} percent of recorded spending',
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: presenter.category(e.key).color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  presenter.category(e.key).name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Text(
                                '${(e.value / total * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
              return size.maxWidth > 420
                  ? Row(
                      children: [
                        ring,
                        const SizedBox(width: 24),
                        Expanded(child: legend),
                      ],
                    )
                  : Column(
                      children: [
                        Center(child: ring),
                        const SizedBox(height: 18),
                        legend,
                      ],
                    );
            },
          ),
        if (largeText && total > 0)
          Text('Recorded spending: ${money(total, presenter.currency)}'),
        if (total > 0)
          ChartValues(
            title: 'View category amounts',
            lines: [
              for (final e in values)
                '${presenter.category(e.key).name}: ${money(e.value, presenter.currency)}',
            ],
          ),
      ],
    );
  }
}

class RingPainter extends CustomPainter {
  final List<({double value, Color color})> values;
  RingPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v.value);
    var start = -math.pi / 2;
    final rect = Offset.zero & size;
    for (final item in values) {
      final sweep = item.value / total * 2 * math.pi;
      canvas.drawArc(
        rect.deflate(14),
        start + .025,
        math.max(0, sweep - .05),
        false,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) => true;
}

class TrendChart extends StatelessWidget {
  final OverviewPresenter presenter;
  const TrendChart({super.key, required this.presenter});
  @override
  Widget build(BuildContext context) {
    final values = (presenter.summary['trend'] as List? ?? []).cast<Json>();
    final maxValue = values.fold<num>(
      1,
      (m, e) => math.max(m, math.max(e['income'] as num, e['expense'] as num)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The bigger picture',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Income and expenses · last 6 months',
          style: TextStyle(color: mutedInk),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 18,
          runSpacing: 8,
          children: [
            legend('Income', green),
            legend('Expenses', const Color(0xFFC4D79D)),
          ],
        ),
        const SizedBox(height: 18),
        Semantics(
          label:
              'Monthly comparison. ${values.map((e) => '${e['month']}, income ${money(e['income'], presenter.currency)}, expenses ${money(e['expense'], presenter.currency)}').join('. ')}',
          excludeSemantics: true,
          child: SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (e) => Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final key in ['income', 'expense'])
                                  Flexible(
                                    child: Tooltip(
                                      message:
                                          '${key == 'income' ? 'Income' : 'Expenses'}: ${money(e[key], presenter.currency)}',
                                      child: Container(
                                        width: 20,
                                        height: math.max(
                                          3,
                                          e[key] / maxValue * 142,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: key == 'income'
                                              ? green
                                              : const Color(0xFFC4D79D),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            [
                              'Jan',
                              'Feb',
                              'Mar',
                              'Apr',
                              'May',
                              'Jun',
                              'Jul',
                              'Aug',
                              'Sep',
                              'Oct',
                              'Nov',
                              'Dec',
                            ][int.parse(e['month'].toString().substring(5)) -
                                1],
                            style: const TextStyle(
                              fontSize: 11,
                              color: mutedInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        ChartValues(
          title: 'View monthly amounts',
          lines: [
            if (values.isEmpty) 'No monthly records available.',
            for (final e in values)
              '${e['month']}: income ${money(e['income'], presenter.currency)}; expenses ${money(e['expense'], presenter.currency)}',
          ],
        ),
      ],
    );
  }

  Widget legend(String title, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class DailyChart extends StatelessWidget {
  final OverviewPresenter presenter;
  const DailyChart({super.key, required this.presenter});
  @override
  Widget build(BuildContext context) {
    final daily = presenter.summary['daily_expenses'] as Json? ?? {};
    final days = DateTime(
      presenter.month.year,
      presenter.month.month + 1,
      0,
    ).day;
    final values = List.generate(
      days,
      (i) =>
          (daily[dateOf(
                        DateTime(
                          presenter.month.year,
                          presenter.month.month,
                          i + 1,
                        ),
                      )]
                      as num? ??
                  0)
              .toDouble(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your daily rhythm',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Daily expenses · peak ${money(values.reduce(math.max), presenter.currency)}',
          style: const TextStyle(color: mutedInk),
        ),
        const SizedBox(height: 24),
        Semantics(
          label:
              'Daily spending line chart. ${daily.entries.map((e) => '${e.key}: ${money(e.value, presenter.currency)}').join(', ')}',
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(painter: LinePainter(values)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('1', style: TextStyle(color: mutedInk)),
            Text('$days', style: const TextStyle(color: mutedInk)),
          ],
        ),
        ChartValues(
          title: 'View daily amounts',
          lines: [
            if (daily.isEmpty) 'No expenses recorded for this month.',
            for (final day in daily.keys.toList()..sort())
              '$day: ${money(daily[day], presenter.currency)}',
            'Other dates have no recorded expenses. Missing activity cannot be detected.',
          ],
        ),
      ],
    );
  }
}

class ChartValues extends StatelessWidget {
  final String title;
  final List<String> lines;
  const ChartValues({super.key, required this.title, required this.lines});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(title),
    children: [
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(alignment: Alignment.centerLeft, child: Text(line)),
        ),
    ],
  );
}

class LinePainter extends CustomPainter {
  final List<double> values;
  LinePainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final peak = math.max(1.0, values.reduce(math.max));
    final line = Paint()
      ..color = const Color(0xFFE8EDE2)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - 8 - values[i] / peak * (size.height - 16);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x4434785B), Color(0x0034785B)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) => true;
}
