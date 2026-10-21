# Debt repayment planner

Reports → Debt repayment planner compares snowball (smallest remaining balance
first) and avalanche (highest annual rate first), plus avalanche without extra
payments. Enter a first payment month, each debt's current balance, annual rate
and fixed minimum, and an explicit extra monthly amount (zero allowed).

Calculations run locally. Explicitly saved scenario snapshots persist to your
account; calculations never call an AI provider or change existing debt schedules. Missing rates are not assumed to be zero.
The screen does not check the proposed budget against reconciled cash.

Interest accrues before each monthly payment, using annual rate / 12 rounded
half-up to minor units. Each debt receives up to its fixed minimum; remaining
budget is applied in strategy order. Cleared minimums roll over immediately.
Snowball sorts balances after minimum payments; ties use input order. The monthly
budget stays fixed. Dates are month estimates, not contractual due dates.

No fees, daily-interest calculations, promotional rates, variable minimums or new
borrowing are modeled. Simulations stop after 600 months or when any growing
balance exceeds 100 billion minor units, and show remaining debt rather than a
false payoff estimate. Inputs support up to 20 debts and annual rates 0–100%.
Edits invalidate results. Closing the screen discards unsaved inputs.


## Import and saved scenarios

Import saved debts loads active, non-expired debt schedules. Known outstanding
balances and monthly payment amounts prefill the form. These are declared inputs,
not statement balances recalculated from payments. Interest rates remain blank
because debt schedules do not contain them; non-monthly payments also remain
blank. Review all values. More than 20 debts requires manual selection by entry.
Importing or loading a scenario asks before replacing unsaved inputs.

Give a scenario a name and use Save scenario snapshot to store its assumptions.
Reopen a saved entry to review and recalculate it; edited assumptions save as a
new snapshot. Unchanged save retries reuse the same operation ID. Delete scenarios
from the list with confirmation. Up to 30 snapshots per account are supported.

GET /debt-planner, POST /debt-scenarios and DELETE /debt-scenarios/{id} use the
existing authenticated repository. Scenarios are owner-scoped encrypted documents
in the existing document table; no SQL migration is required. Save retries are
idempotent and enforce matching payloads. Scenarios are included in account export
and account deletion. Signing out clears loaded data and form inputs; late replies
from a former account are discarded. Saving/importing requires connectivity;
manual calculations remain local. Cash-affordability integration remains pending.
