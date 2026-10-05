# Protected funding

Implemented 2026-10-02 (Slice 5). Open **Settings → Financial plan → Open protected funding**. Wishlist items, purchase readiness, forecasts and purchase/reversal flows remain Slice 6.

## Workflow

1. Review the financial profile and debt list in Financial plan. Gross/net income is not used as current cash.
2. **Reconcile cash**: enter actual balances of included cash/debit/e-wallet accounts, an as-of timestamp and an explicit confirmation that spending and earmarked reserves in these accounts are included. Enter a named account with zero when there is no cash. Never enter credit limits or expected income.
3. Create emergency or other savings goals. A target does not allocate money. Mark balances held outside included accounts separately; these balances neither increase cash nor reduce it again as a reserve.
4. **Review funding plan**: confirm the next income date, remaining essential allowances, cash buffer and future monthly surplus. A blank income date explicitly selects 30 days including today. Empty allowances explicitly mean no additional essentials. Buffer and surplus require entered values, including zero; surplus may be negative.
5. Explicitly **Reserve cash**, **Release cash** or **Move reservation**. These actions only change earmarks; they create no banking transfers, expenses or income. History records each successful reservation change once.

## Calculation and review rules

All amounts use integer minor units of the account currency. Future income and monthly forecast surplus never add to current funding.

`free_to_allocate = max(0, L - O - E - G - B)`

`coverage_shortfall = max(0, O + E + G + B - L)`

- **L**: reconciled liquid cash across included accounts.
- **O**: remaining scheduled debts/bills (including overdue occurrences and declared extra debt payments), additional essential allowances, and unfunded required savings due within the horizon.
- **E / G**: cash reserved for emergency / other savings goals inside L.
- **B**: a separately declared cash buffer.

Wishlist reservations are included in protected cash alongside emergency and other savings. Paused and archived items retain their funds until explicit release or reallocation.

An allowance is its **remaining total, including linked scheduled items**. Each schedule can be linked to at most one allowance. Additional protection is `max(0, allowance total - linked unpaid occurrences)`; all scheduled unpaid amounts are still protected independently. After a payment, review the remaining allowance rather than automatically guessing which other essentials remain.

A goal's optional `required_amount` is the **minimum funded reserve required by `required_by`**, not an additional recurring transfer. Its unfunded difference is included in O when due within the horizon. Funding it moves protection from O into E/G, so the same money is never counted twice. Users review/update dated requirements for later periods; automatic recurring saving contributions are not implemented.

Every debt and recurring bill is conservatively protected. The assessment includes all known overdue occurrences from each schedule's start date, including closed schedules with unpaid history. It fails closed after 10,000 occurrences rather than silently dropping history. Resolve incorrect schedules or payment history in Financial plan.

A cash snapshot must be no more than 24 hours old. Known transaction creation/edit/deletion and payment linking invalidate it using a monotonic cash revision. The plan must be reviewed on the user's current local date and after changes to goals, debt/bill schedules, profile or payment links. A confirmed next income date may be today through 366 days ahead. Incomplete inputs return null available cash/shortfall; stale but complete arithmetic remains visible for review and cannot authorize contributions.

Reconciliation may truthfully reveal a coverage shortfall. New allocations and reallocations must leave all protections covered. Explicit releases remain possible after refreshing the current revisions, even with stale/incomplete funding inputs; releasing does not spend cash, and a required reserve's unfunded amount returns to O. Funded goals cannot be deleted or moved outside included accounts without explicit release/reallocation.

## Persistence and concurrency

The existing private `pocketwise.documents` table holds one `funding` document per owner: snapshot, plan, goals, reservation balances, monotonic revisions and operation replay results. Separate `funding_events` documents form the append-only reservation ledger. No schema migration or client database grants are needed.

All funding mutations, ordinary transaction mutations, planning payment writes and account deletion use the same owner transaction lock. In Supabase this is a Postgres transaction with an owner advisory lock. Ledger insert, reservation update, revision increment and idempotency result either all commit or all roll back. Competing writes cannot both consume the same free cash. Cash recording still succeeds when funding becomes stale or uncovered; the app never blocks a real expense because it was not planned.

Allocation operations require funding and planning revisions, account currency and an operation ID. Replaying the same operation/body returns its original result even after a later revision; changed monetary intent with the same key conflicts. Retries may carry refreshed revision tokens because revisions are preconditions, not operation identity. Account export excludes internal replay metadata and includes funding plus its events; account deletion removes both.

History is paginated in the API/UI, currently after an owner-scoped repository query in memory. Aggregate growth, history indexing/pagination in SQL, and production performance remain release-hardening work.

## API

| Route | Behavior |
|---|---|
| `GET /funding/availability`, `/funding/snapshot`, `/funding/plan`, `/goals` | Same consistent owner aggregate view, including revisions, goal balances, cash breakdown, obligations, allowances and completeness/freshness reasons |
| `PUT /funding/snapshot` | Confirm named account balances and timezone-aware as-of time |
| `PUT /funding/plan` | Confirm income date or 30-day fallback, allowances, buffer and forecast surplus |
| `POST /goals`, `PUT /goals/{id}` | Create/update emergency or savings goals; changing a target never changes funding |
| `DELETE /goals/{id}?expected_revision=` | Reject funded-goal deletion |
| `POST /funding/allocations`, `/funding/releases`, `/funding/reallocations` | Positive integer amount, operation ID and revision-protected cash reservations |
| `GET /funding/events?page=1&page_size=20` | Owner history, newest first; max page size 100 |

The generated API `/docs` defines request fields. Goal writes require `expected_revision`; cash/plan/allocation writes also require `expected_planning_revision`. Caller-supplied ownership fields are rejected. The server derives ownership from authentication.

## Verification

Local API/domain tests cover missing versus zero, explicit confirmation, horizons, allowance linking, partial bill payments and cash reconciliation, outside savings, required savings, releases/reallocations, stale cash, currency/ownership, revision conflicts, retries, export/deletion and rollback. Presenter/widget tests cover stale reads, logout/disposal, retry keys, duplicate submissions, explicit confirmations and a phone at 200% text size.

Live Supabase tests use two independent pools to verify same-key retries, competing allocations, event/aggregate rollback, transaction/cash-marker rollback and the expense-versus-allocation race. Wishlist tests additionally cover purchase retries, competing purchases and rollback of purchases, refunds and link corrections. Native-device journeys remain unverified. See [TESTING.md](TESTING.md) for run results.
