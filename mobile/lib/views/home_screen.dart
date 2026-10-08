import 'financial_helper_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/presentation/app_presenters.dart';
import '../core/model/contracts.dart';
import '../core/view/presenter_builder.dart';
import '../core/view/category_style.dart';
import '../features/overview/presenter/overview_presenter.dart';
import '../main.dart';
import '../models/finance.dart';
import '../widgets/charts.dart';
import 'entry_editor.dart';
import 'profile_editor.dart';
import 'transaction_filters.dart';
import 'planning_screen.dart';
import 'sync_screen.dart';
import 'dashboard_plan_summary.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppPresenters presenters;
  const HomeScreen({super.key, required this.presenters});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int page = 0;
  String search = '', filter = 'all';
  String? categoryFilter;
  final searchField = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.presenters.sync?.synchronize();
    }
  }

  OverviewPresenter get c => widget.presenters.overview;
  final titles = ['Overview', 'Transactions', 'Budgets', 'Reports', 'Settings'];
  final icons = [
    Icons.grid_view_rounded,
    Icons.swap_horiz_rounded,
    Icons.donut_large_rounded,
    Icons.bar_chart_rounded,
    Icons.tune_rounded,
  ];
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchField.dispose();
    super.dispose();
  }

  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: c,
    builder: (context, state) => content(context),
  );

  Widget content(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) sidebar(),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 38 : 20,
                      24,
                      wide ? 38 : 20,
                      18,
                    ),
                    child: Row(
                      children: [
                        if (!wide) ...[
                          const Icon(Icons.spa_rounded, color: green),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            wide ? titles[page] : 'pocketwise',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: c.busy ? null : c.reload,
                          icon: const Icon(Icons.refresh_rounded, size: 21),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          backgroundColor: const Color(0xFFE1EBCF),
                          foregroundColor: ink,
                          child: Text(
                            (c.user?.name ?? 'U').substring(0, 1).toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.busy) const LinearProgressIndicator(minHeight: 2),
                  if (widget.presenters.sync != null)
                    SyncBanner(
                      presenter: widget.presenters.sync!,
                      reauthenticate: widget.presenters.auth.signInAgain,
                      currency: c.currency,
                    ),
                  if (c.state.data.cachedAt != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Cached estimate from ${c.state.data.cachedAt}. Pending changes are shown in Offline & sync and are not included in these totals.',
                      ),
                    ),
                  if (c.error != null)
                    MaterialBanner(
                      content: Text(c.error!),
                      actions: [
                        TextButton(
                          onPressed: c.reload,
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              if (!await widget.presenters.auth.logout()) {
                                message(
                                  widget.presenters.auth.state.error ??
                                      "Unable to sign out",
                                );
                              }
                            } catch (e) {
                              message(e);
                            }
                          },
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: c.reload,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          wide ? 38 : 20,
                          16,
                          wide ? 38 : 20,
                          36,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1300),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (page != 4) heading(),
                              const SizedBox(height: 26),
                              if (page == 0) dashboard(),
                              if (page == 1)
                                PresenterBuilder(
                                  presenter: widget.presenters.history,
                                  builder: (_, state) => transactions(),
                                ),
                              if (page == 2) budgets(),
                              if (page == 3) reports(),
                              if (page == 4) settings(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: List.generate(
                5,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: titles[i],
                ),
              ),
            ),
    );
  }

  Widget sidebar() => Container(
    width: 224,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: Color(0xFFE7EBE2))),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 34),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 48),
          child: Row(
            children: [
              Icon(Icons.spa_rounded, color: green, size: 30),
              SizedBox(width: 10),
              Text(
                'pocketwise',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 16),
          child: Text(
            'YOUR SPACE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.7,
              color: mutedInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: page == i ? const Color(0xFFEAF0E2) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                leading: Icon(
                  icons[i],
                  color: page == i ? green : const Color(0xFF88928B),
                  size: 21,
                ),
                title: Text(
                  titles[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: page == i ? FontWeight.w700 : FontWeight.w500,
                    color: page == i ? ink : mutedInk,
                  ),
                ),
                onTap: () => setState(() => page = i),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6EC),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wb_sunny_outlined, color: green),
              SizedBox(height: 14),
              Text(
                'Small steps.\nBrighter tomorrows.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.5),
              ),
              SizedBox(height: 8),
              Text(
                'A little awareness goes a long way.',
                style: TextStyle(fontSize: 12, color: mutedInk, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'A little clarity, every day.',
            style: TextStyle(fontSize: 10, color: mutedInk),
          ),
        ),
      ],
    ),
  );
  Widget heading() => LayoutBuilder(
    builder: (context, size) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page == 0
                ? 'Your money, at a glance.'
                : page == 1
                ? 'Every little detail.'
                : page == 2
                ? 'A plan for what matters.'
                : 'See your money story.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            page == 0
                ? 'Welcome back, ${c.user?.name}. Let’s make today count.'
                : page == 1
                ? 'All your ins and outs, in one calm place.'
                : page == 2
                ? 'Give your spending a little direction.'
                : 'Find the patterns. Build better habits.',
            style: const TextStyle(color: mutedInk, fontSize: 14),
          ),
        ],
      );
      final month = Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E8DD)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: c.busy ? null : () => c.changeMonth(-1),
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
            Text(
              DateFormat('MMM yyyy').format(c.month),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: c.busy ? null : () => c.changeMonth(1),
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
      );
      return size.maxWidth > 720
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                month,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 18), month],
            );
    },
  );
  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
  Widget adaptivePair(Widget left, Widget right, {double breakpoint = 750}) =>
      LayoutBuilder(
        builder: (context, size) => size.maxWidth > breakpoint
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 22),
                  Expanded(child: right),
                ],
              )
            : Column(children: [left, const SizedBox(height: 22), right]),
      );
  Widget dashboard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PresenterBuilder(
        presenter: widget.presenters.planning,
        builder: (context, state) {
          final unpaid = state
              .items('occurrences')
              .where(
                (item) =>
                    item['remaining_amount'] == null ||
                    (item['remaining_amount'] as int) > 0,
              )
              .take(5)
              .toList();
          if (unpaid.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Planned obligations · ${DateFormat('MMMM yyyy').format(state.month)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.error != null)
                    const Text(
                      'Plan could not refresh; these dates may be out of date.',
                    ),
                  for (final item in unpaid)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${item['due_date']} · ${item['name']} · ${item['remaining_amount'] == null ? 'Amount unknown' : money(item['remaining_amount'], c.currency)} unpaid${item['overdue'] == true ? ' · overdue' : ''}',
                      ),
                    ),
                  TextButton(
                    onPressed: openPlanning,
                    child: const Text('View financial plan'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      LayoutBuilder(
        builder: (context, size) {
          final cards = [
            balanceCard(),
            metric(
              'Money in',
              c.summary['income'] ?? 0,
              Icons.south_west_rounded,
              'Income this month',
              green,
            ),
            metric(
              'Money out',
              c.summary['expenses'] ?? 0,
              Icons.north_east_rounded,
              'Expenses this month',
              const Color(0xFFB97950),
            ),
          ];
          if (size.maxWidth > 850) {
            return Row(
              children: [
                Expanded(flex: 12, child: cards[0]),
                const SizedBox(width: 18),
                Expanded(flex: 10, child: cards[1]),
                const SizedBox(width: 18),
                Expanded(flex: 10, child: cards[2]),
              ],
            );
          }
          return Column(
            children: [
              cards[0],
              const SizedBox(height: 16),
              if (MediaQuery.textScalerOf(context).scale(14) > 20) ...[
                SizedBox(width: double.infinity, child: cards[1]),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: cards[2]),
              ] else
                Row(
                  children: [
                    Expanded(child: cards[1]),
                    const SizedBox(width: 14),
                    Expanded(child: cards[2]),
                  ],
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF1E3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, size) {
            final intro = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.auto_awesome_outlined, color: green),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Less typing. More living.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '“Spent 15 on lunch yesterday” — just say it naturally.',
                        style: TextStyle(
                          color: mutedInk,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final action = FilledButton.icon(
              onPressed: c.categories.isEmpty
                  ? null
                  : () => showEntryEditor(
                      context,
                      widget.presenters,
                      natural: true,
                    ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Quick entry'),
            );
            return size.maxWidth > 650
                ? Row(
                    children: [
                      Expanded(child: intro),
                      const SizedBox(width: 18),
                      action,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [intro, const SizedBox(height: 16), action],
                  );
          },
        ),
      ),
      const SizedBox(height: 22),
      adaptivePair(
        panel(SpendingChart(presenter: c)),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(
                'Staying on track',
                'All budgets',
                () => setState(() => page = 2),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your monthly spending plans',
                style: TextStyle(color: mutedInk),
              ),
              const SizedBox(height: 22),
              if (c.budgets.isEmpty)
                empty(
                  'A little plan goes a long way.',
                  'Set your first monthly budget.',
                  Icons.donut_large_rounded,
                )
              else
                ...c.budgets.take(3).map((b) => budgetRow(b)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      panel(
        Column(
          children: [
            sectionTitle(
              'Recent transactions',
              'View all',
              () => setState(() => page = 1),
            ),
            const SizedBox(height: 16),
            if (c.entries.isEmpty)
              empty(
                'Your fresh start.',
                'Add your first transaction to get going.',
                Icons.receipt_long_outlined,
              )
            else
              ...c.entries.take(5).map(entryRow),
          ],
        ),
      ),
      const SizedBox(height: 22),
      panel(
        DashboardPlanSummary(
          summary: c.summary,
          currency: c.currency,
          stale: c.state.stale || c.state.data.cachedAt != null,
          openHelper: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  FinancialHelperScreen(presenter: widget.presenters.helper),
            ),
          ),
          openWishlist: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  WishlistScreen(presenter: widget.presenters.funding),
            ),
          ),
        ),
      ),
    ],
  );
  Widget balanceCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Total balance',
                style: TextStyle(color: Color(0xFFD2DFD0), fontSize: 13),
              ),
            ),
            Icon(
              Icons.account_balance_wallet_outlined,
              color: Color(0xFFCEE79E),
              size: 20,
            ),
          ],
        ),
        const SizedBox(height: 21),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            money(c.summary['balance'] ?? 0, c.currency),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Across your recorded transactions',
          style: TextStyle(color: Color(0xFFB7C9B7), fontSize: 11),
        ),
      ],
    ),
  );
  Widget metric(
    String title,
    num amount,
    IconData icon,
    String caption,
    Color color,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: mutedInk, fontSize: 13),
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 21),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              money(amount, c.currency),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(caption, style: const TextStyle(fontSize: 11, color: mutedInk)),
        ],
      ),
    ),
  );
  Widget sectionTitle(String title, String action, VoidCallback onTap) {
    final heading = Text(title, style: Theme.of(context).textTheme.titleLarge);
    final button = TextButton(
      onPressed: onTap,
      child: Text(action, style: const TextStyle(fontSize: 12)),
    );
    return MediaQuery.textScalerOf(context).scale(12) > 17
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, button],
          )
        : Row(
            children: [
              Expanded(child: heading),
              button,
            ],
          );
  }

  Widget empty(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFFAAB99C)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: mutedInk),
          ),
        ],
      ),
    ),
  );
  Widget entryRow(Entry entry) {
    final category = c.category(entry.categoryId);
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 19;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showEntryEditor(context, widget.presenters, entry: entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(category.symbol, color: category.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.note.isEmpty ? category.name : entry.note,
                    maxLines: largeText ? null : 1,
                    overflow: largeText
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${category.name} · ${DateFormat('MMM d').format(entry.date)}',
                    style: const TextStyle(fontSize: 11, color: mutedInk),
                  ),
                  if (largeText)
                    Text(
                      '${entry.type == 'income' ? '+' : '−'}${money(entry.amount, c.currency)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: entry.type == 'income' ? green : ink,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (!largeText)
              Text(
                '${entry.type == 'income' ? '+' : '−'}${money(entry.amount, c.currency)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: entry.type == 'income' ? green : ink,
                ),
              ),
            if (page == 1)
              PopupMenuButton<String>(
                tooltip: 'Transaction actions',
                onSelected: (value) async {
                  if (value == 'edit') {
                    showEntryEditor(context, widget.presenters, entry: entry);
                  } else if (await confirm(
                    'Delete transaction?',
                    'This removes this transaction from your reports and budgets.',
                  )) {
                    try {
                      if (!await widget.presenters.transactions.delete(
                        entry.id,
                        expectedVersion: entry.version,
                      )) {
                        message(
                          widget.presenters.transactions.state.error ??
                              "Unable to delete transaction",
                        );
                      }
                    } catch (e) {
                      message(e);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void applyHistoryFilters() {
    final h = widget.presenters.history;
    final f = h.state.filter;
    h.apply(
      EntryFilter(
        start: f.start,
        end: f.end,
        query: search,
        type: filter,
        categoryId: categoryFilter,
        minAmount: f.minAmount,
        maxAmount: f.maxAmount,
      ),
    );
  }

  Widget transactions() {
    final history = widget.presenters.history;
    final visible = history.state.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (history.state.cachedAt != null)
          Text(
            'Cached transactions from ${history.state.cachedAt}. Pending changes are listed in Offline & sync.',
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: c.categories.isEmpty
                  ? null
                  : () => showEntryEditor(context, widget.presenters),
              icon: const Icon(Icons.add),
              label: const Text('Add transaction'),
            ),
            OutlinedButton.icon(
              onPressed: c.categories.isEmpty
                  ? null
                  : () => showEntryEditor(
                      context,
                      widget.presenters,
                      natural: true,
                    ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Natural entry'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: searchField,
                onChanged: (v) {
                  setState(() => search = v);
                  applyHistoryFilters();
                },
                decoration: const InputDecoration(
                  hintText: 'Search notes or categories',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in ['all', 'expense', 'income'])
                    ChoiceChip(
                      label: Text(
                        value == 'all'
                            ? 'All transactions'
                            : value == 'expense'
                            ? 'Expenses'
                            : 'Income',
                      ),
                      selected: filter == value,
                      onSelected: (_) {
                        setState(() => filter = value);
                        applyHistoryFilters();
                      },
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Filter category',
                    onSelected: (v) {
                      setState(() => categoryFilter = v == 'all' ? null : v);
                      applyHistoryFilters();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'all',
                        child: Text('All categories'),
                      ),
                      ...c.categories.map(
                        (cat) =>
                            PopupMenuItem(value: cat.id, child: Text(cat.name)),
                      ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.filter_list, size: 17),
                      label: Text(
                        categoryFilter == null
                            ? 'Category'
                            : c.category(categoryFilter!).name,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune),
                    label: const Text('Date & amount'),
                    onPressed: () async {
                      final selected = await showDialog<EntryFilter>(
                        context: context,
                        builder: (_) => TransactionFilters(
                          filter: history.state.filter,
                          currency: c.currency,
                        ),
                      );
                      if (selected != null) await history.apply(selected);
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        search = '';
                        filter = 'all';
                        categoryFilter = null;
                        searchField.clear();
                      });
                      history.apply(
                        EntryFilter(
                          start: DateTime(c.month.year, c.month.month),
                          end: DateTime(c.month.year, c.month.month + 1, 0),
                        ),
                      );
                    },
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
              Text(
                '${dateOf(history.state.filter.start)} – ${dateOf(history.state.filter.end)}',
              ),
              if (history.state.filter.minAmount != null ||
                  history.state.filter.maxAmount != null)
                Text(
                  'Amount: ${history.state.filter.minAmount == null ? 'No minimum' : money(history.state.filter.minAmount!, c.currency)} – ${history.state.filter.maxAmount == null ? 'No maximum' : money(history.state.filter.maxAmount!, c.currency)}',
                ),
              const SizedBox(height: 16),
              if (history.state.busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading transactions',
                ),
              if (history.state.error != null) ...[
                Text(
                  history.state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: history.reload,
                  child: const Text('Retry transactions'),
                ),
              ],
              Text(
                '${visible.length} of ${history.state.total} transactions',
                style: const TextStyle(fontSize: 12, color: mutedInk),
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty &&
                  !history.state.busy &&
                  history.state.error == null)
                empty(
                  'Nothing here yet.',
                  'Try another filter or add a transaction.',
                  Icons.search_rounded,
                )
              else
                ...visible.map(entryRow),
              if (visible.length < history.state.total)
                OutlinedButton(
                  onPressed: history.state.busy ? null : history.loadMore,
                  child: const Text('Load more transactions'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget budgetRow(Json b, {bool editable = false}) {
    final amount = b['limit_amount'] as int, spent = b['spent'] as int;
    final ratio = spent / amount;
    final near = ratio * 100 >= (b['alert_threshold'] as int);
    final color = ratio >= 1
        ? const Color(0xFFA84435)
        : near
        ? const Color(0xFF856014)
        : green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b['category_id'] == null
                      ? 'Overall monthly budget'
                      : c.category(b['category_id']).name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (editable)
                PopupMenuButton<String>(
                  tooltip: 'Budget actions',
                  onSelected: (v) async {
                    if (v == 'edit') {
                      budgetEditor(b);
                    } else if (await confirm(
                      'Remove budget?',
                      'Your transactions will stay in your account.',
                    )) {
                      try {
                        if (!await widget.presenters.budgets.delete(b['id'])) {
                          message(
                            widget.presenters.budgets.state.error ??
                                'Unable to delete budget',
                          );
                        }
                      } catch (e) {
                        message(e);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 7,
              color: color,
              backgroundColor: const Color(0xFFEDF0E7),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                '${money(spent, c.currency)} of ${money(amount, c.currency)}',
                style: const TextStyle(fontSize: 11, color: mutedInk),
              ),
              Text(
                '${money((amount - spent).abs(), c.currency)} ${spent > amount ? 'over budget' : 'left'}',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
          if (near)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                ratio >= 1
                    ? 'You’ve reached this budget. Time to review your plan.'
                    : 'You’ve reached your ${b['alert_threshold']}% alert threshold.',
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
        ],
      ),
    );
  }

  void openPlanning() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlanningScreen(presenters: widget.presenters),
    ),
  );

  Widget budgets() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: c.categories.isEmpty ? null : () => budgetEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Set a budget'),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: openPlanning,
        icon: const Icon(Icons.event_note),
        label: const Text('Plan income, debts & bills'),
      ),
      const SizedBox(height: 22),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A little intention goes a long way.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Track the whole month or make room for a specific category.',
              style: TextStyle(color: mutedInk),
            ),
            const SizedBox(height: 28),
            if (c.budgets.isEmpty)
              empty(
                'Make your first plan.',
                'Set an overall or category budget above.',
                Icons.donut_large_rounded,
              )
            else
              ...c.budgets.map((b) => budgetRow(b, editable: true)),
          ],
        ),
      ),
    ],
  );
  Future<void> budgetEditor([Json? budget]) async {
    final amount = TextEditingController(
      text: budget == null
          ? ''
          : (budget['limit_amount'] / 100).toStringAsFixed(2),
    );
    final threshold = TextEditingController(
      text: '${budget?['alert_threshold'] ?? 80}',
    );
    var cat = budget?['category_id'] as String? ?? 'all';
    final presenter = widget.presenters.budgets;
    final form = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (context) => PresenterBuilder(
        presenter: presenter,
        builder: (context, state) => AlertDialog(
          title: Text(
            budget == null ? 'Make a little plan' : 'Adjust your budget',
          ),
          content: SizedBox(
            width: 400,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('For ${DateFormat.yMMMM().format(c.month)}'),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: cat,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Overall budget'),
                      ),
                      ...c.categories
                          .where((cat) => cat.type == 'expense')
                          .map(
                            (cat) => DropdownMenuItem(
                              value: cat.id,
                              child: Text(cat.name),
                            ),
                          ),
                    ],
                    onChanged: budget != null ? null : (v) => cat = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Monthly limit (${c.currency})',
                    ),
                    validator: presenter.validateAmount,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: threshold,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Alert at (%)',
                    ),
                    validator: presenter.validateThreshold,
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        state.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
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
                      final saved = await presenter.save(
                        BudgetDraft(
                          categoryId: cat == 'all' ? null : cat,
                          period: c.period,
                          limitAmount: minorUnits(amount.text)!,
                          alertThreshold: int.parse(threshold.text),
                        ),
                      );
                      if (context.mounted && saved) Navigator.pop(context);
                    },
              child: Text(state.busy ? 'Saving…' : 'Save budget'),
            ),
          ],
        ),
      ),
    );
    // Dialog routes animate out before disposing their text fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    amount.dispose();
    threshold.dispose();
  }

  Widget reports() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      monthlyReview(),
      const SizedBox(height: 22),
      adaptivePair(
        panel(SpendingChart(presenter: c)),
        panel(TrendChart(presenter: c)),
      ),
      const SizedBox(height: 22),
      panel(DailyChart(presenter: c)),
      const SizedBox(height: 22),
      panel(
        Row(
          children: [
            const Icon(Icons.lightbulb_outline, color: green),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'This month, ${money(c.summary['income'] ?? 0, c.currency)} came in and ${money(c.summary['expenses'] ?? 0, c.currency)} went out. Your net change is ${money(c.summary['net'] ?? 0, c.currency)}.',
                style: const TextStyle(height: 1.6),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget monthlyReview() {
    final review = c.summary['review'] as Map?;
    if (review == null) return const SizedBox.shrink();
    final status = review['period_status'];
    final budgets = (review['budget_variances'] as List).cast<Json>();
    final change = review['expense_change'] as int;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly review', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            status == 'in_progress'
                ? 'Month in progress · totals are partial'
                : status == 'future'
                ? 'Future month · entries may be planned'
                : 'Month ended · recorded activity only',
          ),
          const SizedBox(height: 8),
          Text(
            '${review['record_count']} entries across ${review['recorded_days']} days.',
          ),
          Text(review['coverage'] as String),
          const SizedBox(height: 12),
          Text(
            'Recorded income: ${money(c.summary['income'] ?? 0, c.currency)}',
          ),
          Text(
            'Recorded spending: ${money(c.summary['expenses'] ?? 0, c.currency)}',
          ),
          Text(
            'Net recorded change: ${money(c.summary['net'] ?? 0, c.currency)}',
          ),
          if (review['previous_record_count'] == 0)
            const Text(
              'No previous-month entries are available for comparison.',
            )
          else
            Text(
              'Spending is ${money(change.abs(), c.currency)} ${change < 0 ? 'lower' : 'higher'} than ${review['previous_month']}. Compare only periods with similar recording coverage.',
            ),
          const SizedBox(height: 20),
          Text('Budget review', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Overall and category limits overlap; they are reviewed separately.',
          ),
          if (budgets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No budgets set for this month.'),
            ),
          ...budgets.map((budget) => budgetRow(budget)),
          const SizedBox(height: 12),
          if (review['debt_ratios'] != null) ...[
            HelperResultCard(
              result: review['debt_ratios'] as Json,
              title: 'Debt ratios · declared schedules',
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FinancialHelperScreen(
                    presenter: widget.presenters.helper,
                  ),
                ),
              ),
              child: const Text('Open financial helper'),
            ),
          ],
          if (review['funding'] != null) ...[
            Text(
              'Savings and wishlist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Current reservations as of ${review['funding']['as_of']}; these are not historical month-end balances.',
            ),
            Text(
              'Emergency: ${money(review['funding']['current_reserves']['emergency_reserved'], c.currency)} · Savings: ${money(review['funding']['current_reserves']['savings_reserved'], c.currency)} · Wishlist: ${money(review['funding']['current_reserves']['wishlist_reserved'], c.currency)}',
            ),
            if (review['funding']['usable'] != true)
              const Text('Cash and plan need review.'),
            Text(
              'Wishlist purchases this month: ${review['funding']['purchase_count']} · ${money(review['funding']['purchase_total'], c.currency)}',
            ),
            Text(
              'Recorded wishlist refunds this month: ${money(review['funding']['refund_total'], c.currency)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Make yourself at home.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 24),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.user?.name ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(c.user?.email ?? ''),
            const SizedBox(height: 12),
            PresenterBuilder(
              presenter: widget.presenters.auth,
              builder: (context, state) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.busy
                        ? null
                        : () {
                            widget.presenters.auth.clearError();
                            showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => ProfileEditor(
                                presenter: widget.presenters.auth,
                              ),
                            );
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.busy
                        ? null
                        : () async {
                            final destination =
                                widget.presenters.exportDestination;
                            if (destination == null) {
                              message(
                                'File export is unavailable on this device.',
                              );
                              return;
                            }
                            final saved = await widget.presenters.auth
                                .exportData(destination);
                            if (saved) {
                              message('Your data export is ready.');
                            } else if (widget.presenters.auth.state.error !=
                                null) {
                              message(widget.presenters.auth.state.error!);
                            }
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export my data'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Export your profile, transactions, budgets and categories as a JSON file.',
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: openPlanning,
              icon: const Icon(Icons.event_note),
              label: const Text('Financial plan'),
            ),
            const SizedBox(height: 12),
            Text('Account currency: ${c.currency}'),
            if (widget.presenters.sync != null)
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SyncScreen(
                      presenter: widget.presenters.sync!,
                      reauthenticate: widget.presenters.auth.signInAgain,
                      currency: c.currency,
                    ),
                  ),
                ),
                icon: const Icon(Icons.sync),
                label: const Text('Offline & sync'),
              ),
            const SizedBox(height: 12),
            const Text(
              'All amounts use your account currency. Natural entry is processed on the server without an external AI service.',
              style: TextStyle(color: mutedInk, height: 1.6),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  if (!await widget.presenters.auth.logout()) {
                    message(
                      widget.presenters.auth.state.error ??
                          "Unable to sign out",
                    );
                  }
                } catch (e) {
                  message(e);
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(
              'Your categories',
              'Add category',
              () => categoryEditor(),
            ),
            const SizedBox(height: 16),
            ...c.categories.map(
              (cat) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(cat.symbol, color: cat.color),
                title: Text(cat.name),
                subtitle: Text(cat.type, style: const TextStyle(fontSize: 11)),
                trailing: cat.custom
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            categoryEditor(cat);
                          } else if (await confirm(
                            'Delete category?',
                            'You can remove categories that have no transactions or budgets.',
                          )) {
                            try {
                              if (!await widget.presenters.categories.delete(
                                cat.id,
                              )) {
                                message(
                                  widget.presenters.categories.state.error ??
                                      'Unable to delete category',
                                );
                              }
                            } catch (e) {
                              message(e);
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )
                    : const Text(
                        'Default',
                        style: TextStyle(fontSize: 11, color: mutedInk),
                      ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            if (await confirm(
              'Delete your account?',
              'This permanently deletes your account, transactions, categories and budgets.',
            )) {
              try {
                if (!await widget.presenters.auth.deleteAccount()) {
                  message(
                    widget.presenters.auth.state.error ??
                        'Unable to delete account',
                  );
                }
              } catch (e) {
                message(e);
              }
            }
          },
          child: const Text(
            'Delete account and data',
            style: TextStyle(color: Color(0xFFA84435)),
          ),
        ),
      ),
    ],
  );
  Future<void> categoryEditor([FinanceCategory? category]) async {
    final name = TextEditingController(text: category?.name ?? '');
    var type = category?.type ?? 'expense';
    var icon = category?.icon ?? 'category';
    var color = category?.colorHex ?? '#4D8B70';
    final presenter = widget.presenters.categories;
    await showDialog(
      context: context,
      builder: (context) => PresenterBuilder(
        presenter: presenter,
        builder: (context, state) => AlertDialog(
          title: Text(
            category == null ? 'A category of your own' : 'Edit category',
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Category name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Expense'),
                      ),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: category == null ? (v) => type = v! : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: icon,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Icon'),
                    items: {icon, ...categoryIcons.keys}
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Row(
                              children: [
                                Icon(
                                  categoryIcons[value] ??
                                      Icons.category_rounded,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(value.replaceAll('_', ' ')),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: state.busy ? null : (value) => icon = value!,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: color,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Color'),
                    items: {color, ...categoryColors.keys}
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: Color(
                                    int.parse(
                                      value.replaceFirst('#', 'FF'),
                                      radix: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(categoryColors[value] ?? value),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: state.busy ? null : (value) => color = value!,
                  ),
                  if (state.error != null)
                    Text(
                      state.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
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
                      final saved = await presenter.save(
                        CategoryDraft(
                          name: name.text.trim(),
                          type: type,
                          icon: icon,
                          color: color,
                        ),
                        id: category?.id,
                      );
                      if (context.mounted && saved) Navigator.pop(context);
                    },
              child: Text(state.busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
  }
}
