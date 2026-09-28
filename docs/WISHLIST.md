# Guilt-free wishlist specification

Status: required for Release 1; not implemented in the prototype. Covers FR-36–FR-43 and depends on commitments, protected savings and funding data.

## Product promise

Help users plan wanted purchases without taking money away from declared essentials, scheduled debt payments, protected savings or another goal. “Guilt-free” describes a supportive planning experience, not a guarantee about a user's overall financial situation.

**Confirmed user decision:** readiness uses money already saved. Future income and forecast savings only affect a projected target date.

Use calm language: “Ready under your plan,” “Still saving,” “Review your plan,” and “Needs updated information.” No shame-based scores, streak penalties or encouragement to borrow. No purchase, transfer or banking action occurs inside R1; the app records and plans only.

## Wishlist item

Store name, target cost, currency, amount reserved, priority, optional target date, notes, optional reference URL and lifecycle status. Total target cost includes user-entered tax, shipping and fees. Do not assume an online price is the final cost.

The lifecycle is `active`, `paused`, `purchased` or `archived`. Readiness is a derived result, not a status the user can manually force. An active item can be unfunded, partly funded or fully funded without necessarily being ready.

Priority controls suggested order of future allocations. It does not automatically take money from another item. A target-date change cannot manufacture additional savings.

## Funding baseline and horizon

R1 uses a **user-confirmed liquid-funds snapshot** with included accounts, currency, balance and as-of timestamp. It is distinct from the current prototype's incomplete transaction balance. Do not include credit limits, loan proceeds promised but not received, expected salary, investments that cannot be spent immediately, or unconfirmed funds.

The snapshot represents reconciled current cash/debit/e-wallet funds, including any earmarked savings that are also listed as protected reserves. If an emergency fund is in an excluded account, it is already outside liquid funds and must not be subtracted again.

The planning horizon runs from today through the next user-confirmed income date, inclusive. With no confirmed income date, use a clearly displayed 30-day horizon; include known overdue obligations. The future payday establishes the horizon but contributes **zero** available money. The horizon and obligations must be reviewed together, and users cannot shorten it by silently skipping known commitments.

A usable snapshot is at most 24 hours old and has no unreconciled known cash-affecting changes. This is a product freshness rule, not verification of bank balances. New/edited/deleted transactions or changed obligations/reservations invalidate the previous readiness quote. Before recording a purchase, require a current review and server recalculation. Without bank syncing, the user remains responsible for confirming outside spending.

## Money categories and no-double-counting rules

All terms use the same currency and minor units:

- `L`: confirmed liquid funds currently available across the included accounts.
- `O`: unpaid essential expenses and mandatory debt payments due within the horizon, including overdue amounts. Use remaining amounts after linked partial payments.
- `E`: funded emergency reserve contained in L, protected from wishlist purchases.
- `G`: other funded savings reserves contained in L, excluding wishlist allocations and E.
- `W`: all funded wishlist allocations, including paused/archived items that still retain funds.
- `B`: additional cash buffer selected by the user, separate from E and G.

Reservations partition money already inside L. They do not add money to L. O, E, G, W and B must be mutually exclusive uses of cash. Planned but unfunded mandatory savings contributions due within the horizon belong in O until funded; then move that amount into G/E, never both. All manual entries require an explicit zero/none confirmation where applicable; missing data is not assumed zero.

An overall budget is a spending limit, not a separate reserve. Build O from individual unpaid commitments plus user-declared remaining essential-spending allowances. Link recurring items to their allowances so rent, groceries or a loan installment is not reserved twice. Planned discretionary wishlist spending is excluded from O because W covers it.

A credit-card purchase and its later bill payment must not both reduce the same current cash baseline. In R1's manual snapshot workflow, the user reconciles actual liquid funds; outstanding payments belong in O. Existing debt minimums used in ratios are not added again to O if an occurrence already represents them. Users can reserve more than the minimum where they intend to pay more.

## Allocation and readiness formulas

General available funding:

```text
free_to_allocate = max(0, L - O - E - G - W - B)
coverage_shortfall = max(0, O + E + G + W + B - L)
```

A new contribution must be positive and no larger than free_to_allocate. Contributions reserve cash; they create no expense or income transaction. Reallocation reduces one reservation and increases another atomically.

For item i, let `A_i` be its funded allocation and `C_i` its confirmed total purchase cost. A readiness result requires all of the following:

1. Complete, fresh, user-confirmed inputs and a matching server revision.
2. Item is active, C_i > 0, and A_i >= C_i.
3. coverage_shortfall = 0 across **all** reservations.
4. After paying C_i and releasing A_i, the remaining cash still covers all other commitments/reserves:
   `L - C_i >= O + E + G + (W - A_i) + B`.
5. No overdue mandatory commitment or unfunded required saving contribution remains unresolved. A reserved but overdue bill still needs explicit payment resolution before readiness.

Show “Ready under your plan” with input time and assumptions. A shortage or changed commitment overrides “fully funded” and explains the shortfall. Never use a low DSR/DTI alone to authorize wishlist readiness. Ratios describe debt pressure; this feature requires actual cash and protected commitments.

If target cost falls below its allocation, do not automatically reassign the excess. The user may release it, or it is released during purchase recording. If cost rises, show the new shortfall and invalidate any prior quote.

## Forecast date

Users can choose a planned monthly contribution for each active item. Before showing a forecast, require that the sum of all item contributions fits within the user-confirmed monthly surplus after essentials, debt and protected savings. Monthly surplus is a separate forward-looking plan, not current cash.

```text
remaining_target = max(0, target_cost - funded_allocation)
months_needed = ceil(remaining_target / planned_monthly_contribution)
```

The user provides the next planned contribution date. Generate subsequent dates monthly, clamping dates such as the 31st to each month's last day. The target date is the date of the Nth contribution, counting the next contribution as 1. With zero/negative surplus or zero contribution, show no forecast date; explain what is missing. If already funded but not ready, show the blocking reason instead of “buy today.”

Label every forecast “if you save [amount] monthly”; changing a forecast never creates funded allocations. Pause excludes the item from new scheduled contribution suggestions and requires explicit reassignment of its forecast contribution.

## Purchase recording and reversals

1. User confirms that a purchase actually happened, its date, total cost and expense category. Explicitly identify whether the cash snapshot already includes this payment. The new-expense deduction path below requires a prior snapshot excluding it; this purchase is its sole permitted pending cash change. If the snapshot already includes it, use the reconciled path in step 6.
2. Server checks the current funding revision and readiness against the actual amount. A higher amount requires additional funding/review before the dedicated wishlist flow can proceed.
3. One atomic operation creates/links one expense, consumes A_i, marks the item purchased and adjusts the reconciled funding baseline by the actual expense. Any excess allocation becomes unallocated cash.
4. A stable idempotency key makes retried confirmation return the original result. Concurrent purchases must not spend the same funds.
5. Users may still record any real expense through the ordinary tracker, including an unplanned purchase that does not meet readiness rules; the app must never hide real spending. Such an entry marks funding data for review rather than awarding readiness.
6. For a payment already included in a reconciled cash snapshot, use the reconciled path: link its existing expense, or explicitly create the missing expense with `baseline_effect=already_reconciled`. Require a newly confirmed snapshot that includes the payment, consume the allocation without deducting cash again, and mark the item `purchased` with readiness `not_assessed` if no pre-purchase quote existed. Validate owner, currency, amount and that it has not funded another item.
7. Editing/deleting a linked purchase requires a coordinated reversal/reconciliation flow; reject an ordinary transaction edit/delete that would orphan a reservation. A real refund is a separate linked actual event, not a silent history rewrite. Returned funds become unallocated after confirmation; do not automatically re-reserve them.

MongoDB funding/purchase writes require transactions on a replica set or an equivalently proven atomic aggregate design. The current development Compose configuration does not satisfy that requirement yet. The implementation plan must upgrade it before these features are claimed complete.

## Worked examples and acceptance cases

Examples use generic currency units, with no currency conversion implied.

Let L=4,000, O=1,200, E=1,000, G=300, W=600 and B=200. Free funding is 700. The current item's A_i=500; other items reserve 100.

| Case | Action/input | Expected result |
|---|---|---|
| WL-01 Funded purchase | Current item costs 500, all inputs fresh, no overdue items | Ready; after recording: L=3,500, W=100, free funding still 700; exactly one expense |
| WL-02 Partial funding | Target 900; current allocation 500 | Still saving 400, even though free cash could cover it; explicit allocation required |
| WL-03 Shared money | Two concurrent attempts to reserve 500 from free funding 700 | At most one succeeds; the other sees revised availability |
| WL-04 Changed obligations | O increases by 1,000 | Coverage shortfall 300; no item remains ready merely because individually funded |
| WL-05 Forecast | Target 900; allocation 500; contribution 200/month | Two future contributions, provided combined plans fit surplus; not ready today |
| WL-06 No future surplus | Remaining target > 0; contribution 0 | No target-date estimate; no divide by zero |
| WL-07 Paused item | Pause an item with allocation 500 | Funds stay reserved until explicit release/reallocation |
| WL-08 Snapshot incomplete/stale | Missing commitments confirmation, age >24h or known unreconciled event | Needs updated information; no ready result |
| WL-09 Retry purchase | Repeat WL-01 with the same idempotency key | Same linked expense and outcome; no second deduction |
| WL-10 Bill payment | Pay 100 of an unpaid obligation and reconcile L down 100, O down 100 | Free funding unchanged; no duplicate subtraction |
| WL-11 Already recorded expense | Link an existing reconciled 500 expense | No new expense and no second deduction from L |
| WL-12 Savings outside L | Emergency funds held in an excluded account | Do not subtract those same funds again as E |
| WL-13 More cash expected | Payday expected tomorrow, but no savings reserved | No increase in free funding or readiness |
| WL-14 Fully funded but overdue | A_i covers cost; a mandatory bill is overdue | Review plan until overdue commitment resolved |

Acceptance also requires ownership, mixed-currency, partial failure, stale-version, deletion/reversal and rounding tests. None of these tests are implemented yet.
