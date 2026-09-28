# Release 1 implementation plan

Status: revised requirements plan, not completed implementation. MVP means Model–View–Presenter; release scope is called R1. Source of truth: [product requirements](../skills_files/budget_tracker_requirements.md).

## Sequence and exit criteria

| Slice | Work | Exit criteria |
|---|---|---|
| 0. Requirements baseline | Reconcile country-neutral behavior, MVP architecture, financial helper, wishlist and dependencies | Documents agree; formulas/examples and confirmed user choices recorded |
| 1. MVP architecture migration | Extract repository/use-case interfaces and feature presenters; remove View→API calls; separate backend transport/domain | Architecture gates pass; existing auth/transaction/budget/NLP behavior preserved |
| 2. Core tracking completion | Explicit currency selection, profile/reset flow, category appearance, amount filters, in-app review, export and privacy | Required R1 core scenarios work; no country assumed; production gaps visible |
| 3. Financial profile and commitments | Gross/net income sources, debt schedules, recurring occurrences, paid/partial linking and confirmation flows | Complete/incomplete profiles represented correctly; no duplicate debt/paid occurrence accounting |
| 4. Financial helper | DSR/DTI, explanations, scenarios and explicit saved snapshots | FH-01–FH-12 pass; decimal arithmetic and owner isolation tested; presenter's state transitions tested without Flutter |
| 5. Protected funding | Savings/emergency reserves, cash snapshot, horizon, essential allowances, reservation ledger, idempotency/concurrency | Atomic funding contract verified against MongoDB; cash, future surplus and allocations remain distinct |
| 6. Guilt-free wishlist | Items, funding/release/reallocation, readiness, dates, purchase links and reversal handling | WL-01–WL-14 pass; retries/concurrency cannot overspend or double-post; no forecast treated as savings |
| 7. Offline and release hardening | Cache/queue/conflicts, accessible charts/states, deployment security, backups, performance and OS checks | R1 non-functional gates measured; native/Mongo integration verified; unsupported targets resolved explicitly |

Wishlist UI may be prototyped during earlier slices, but readiness cannot be considered complete before the protected-funding model exists. Financial helper and wishlist are required R1 features, not optional future enhancements.

## Core acceptance scenarios

- Create an account with an explicit currency choice; register/login/reset/logout/delete/export correctly.
- Add/edit/delete income and expenses and see consistent monthly totals and budget progress.
- Filter by month, category, type, amount and search text; handle empty/error/offline states.
- Parse a transaction into a draft and confirm before saving.
- Schedule a bill or debt occurrence and link a partial/full payment once; preserve ratio baseline semantics.
- Enter gross/net income and a complete debt list; explain the two ratio denominators and reproduce the financial examples.
- Try a scenario without altering the underlying debt/profile.
- Protect essentials and savings, allocate only existing money, and explain every wishlist readiness result.
- Record a purchase once, retry safely and reconcile later edits/refunds without silent duplication.
- Reopen after restart/offline work, observe freshness and resolve conflicts explicitly.

## Verification by layer

- Model/domain: deterministic financial arithmetic, dates, currency, funding invariants and reversal behavior.
- Presenter: loading/success/error/incomplete/stale states, rejected inputs, duplicate submission prevention and stale-response ordering.
- View: action forwarding, accessible labels, 200% text scaling and representative screen widths.
- API: request/response fixtures, status codes, ownership, revision handling and idempotency.
- Persistence: real MongoDB transaction, index, rollback, concurrent request and restore tests.
- End to end: at least one complete sign-in → financial profile → wishlist funding → confirmed purchase → updated report journey on each supported native platform.

## R2 and later

R2: push notifications, background recurring posting, formatted exports, receipt attachments, feedback learning, broader preferences and a separately specified debt-payoff planner. Later/optional: conversational queries, OCR, anomaly detection, additional languages and currency conversion. Bank sync and external financial actions remain outside the current scope.

Record actual completed slices in [STATUS.md](STATUS.md); a written plan does not mark them done.
