# 30-day cash-flow forecast

Open Reports → 30-day cash-flow forecast. Reconcile cash and review Protected Funding first, then enter additional daily spending and a minimum buffer. Zero must be entered explicitly. Optionally add up to 30 named income or expense events, each with a date and positive amount within the forecast window.

The authenticated, read-only POST /funding/forecast endpoint starts from the funding cash snapshot and projects today plus the following 29 days in the financial profile timezone. It deducts remaining scheduled bills and debt payments, assuming overdue payments happen today. Outflows precede income on the same date to expose temporary shortfalls. The result shows ending cash, minimum cash, first negative balance, first buffer breach, and an event timeline.

Daily spending is additional to scheduled payments; funding allowances are not deducted again. Expected income must not already be included in reconciled cash. Future-dated ordinary transactions are not automatically included. Savings and wishlist reservations remain within gross projected cash, so this projection never authorizes spending or changes available cash.

Missing/stale funding data and unknown required debt amounts block numerical results. Results expire within five minutes, at the next local midnight, or when the cash snapshot expires, whichever comes first. The app clears results on edits, relevant data changes, account changes, and resume; pending/offline transaction sync blocks calculation. There is no background forecast polling or persistence, and no database migration.


Multiple events are sent as an events array with name, date, kind (income/expense)
and positive amount in minor units. Each row appears in the balance timeline.
Older clients can still use the original single-event fields, but requests mixing
nonempty event rows and legacy event fields are rejected to avoid double counting.
Repeated events are counted separately; review entries and avoid duplicating
scheduled obligations or amounts already represented in daily spending or cash.
Adding, editing or removing rows clears the prior result. Event assumptions are
not saved; saved forecast scenarios and comparisons remain future work.
