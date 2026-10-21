import 'dart:math';

class RepaymentDebt {
  final String name;
  final int balance, annualRateBasisPoints, minimumPayment;
  const RepaymentDebt(
    this.name,
    this.balance,
    this.annualRateBasisPoints,
    this.minimumPayment,
  );
}

class RepaymentResult {
  final int months, interest, remaining;
  final List<int?> payoffMonths;
  const RepaymentResult(
    this.months,
    this.interest,
    this.remaining,
    this.payoffMonths,
  );
  bool get paidOff => remaining == 0;
}

/// Fixed monthly budget, monthly interest rounded half-up to minor units.
/// Minimums are fixed amounts; freed payments roll into the priority debt.
RepaymentResult simulateRepayment(
  List<RepaymentDebt> debts,
  int extra, {
  required bool avalanche,
}) {
  if (debts.isEmpty ||
      debts.length > 20 ||
      extra < 0 ||
      extra > 100000000000 ||
      debts.any(
        (d) =>
            d.name.trim().isEmpty ||
            d.balance <= 0 ||
            d.balance > 100000000000 ||
            d.minimumPayment <= 0 ||
            d.minimumPayment > 100000000000 ||
            d.annualRateBasisPoints < 0 ||
            d.annualRateBasisPoints > 10000,
      )) {
    throw ArgumentError(
      'Enter 1–20 debts with positive balances and payments, and annual rates from 0 to 100%.',
    );
  }
  final balances = debts.map((d) => d.balance).toList();
  final payoff = List<int?>.filled(debts.length, null);
  final budget = debts.fold<int>(extra, (sum, d) => sum + d.minimumPayment);
  var interest = 0;
  for (var month = 1; month <= 600; month++) {
    var available = budget;
    for (var i = 0; i < debts.length; i++) {
      final charge =
          (balances[i] * debts[i].annualRateBasisPoints + 60000) ~/ 120000;
      interest += charge;
      balances[i] += charge;
      final payment = min(balances[i], debts[i].minimumPayment);
      balances[i] -= payment;
      available -= payment;
    }
    final order = List<int>.generate(debts.length, (i) => i)
      ..sort((a, b) {
        final primary = avalanche
            ? debts[b].annualRateBasisPoints.compareTo(
                debts[a].annualRateBasisPoints,
              )
            : balances[a].compareTo(balances[b]);
        return primary != 0 ? primary : a.compareTo(b);
      });
    for (final i in order) {
      final payment = min(balances[i], available);
      balances[i] -= payment;
      available -= payment;
      if (balances[i] == 0) payoff[i] ??= month;
    }
    final remaining = balances.fold<int>(0, (a, b) => a + b);
    if (remaining == 0) {
      return RepaymentResult(month, interest, 0, List.unmodifiable(payoff));
    }
    // Stop before values approach JavaScript's exact integer limit on web.
    if (balances.any((b) => b > 100000000000)) {
      return RepaymentResult(
        month,
        interest,
        remaining,
        List.unmodifiable(payoff),
      );
    }
  }
  return RepaymentResult(
    600,
    interest,
    balances.fold<int>(0, (a, b) => a + b),
    List.unmodifiable(payoff),
  );
}
