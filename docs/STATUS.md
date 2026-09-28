# Implementation status

Updated 2026-09-28. The repository contains a working prototype plus a revised Release 1 specification. Documentation changes in the current revision do not implement the new features.

## Prototype capabilities already present

- Flutter Android/iOS/web project with responsive Material 3 screens.
- Registration/login, access/refresh JWTs, refresh rotation, sign-out and account/data deletion for existing entities.
- Transaction CRUD, monthly history, note/category search and type/category filtering; API also accepts amount/date filters and pagination.
- Default categories and custom creation/rename/delete; backend icon/color fields.
- Monthly overall/category budgets and on-screen threshold alerts.
- Recorded balance, income/expenses, recent activity, category donut, monthly comparison and daily trend charts.
- Local English parsing with review/confirmation before saving.
- Persistent SQLite development repository, a MongoDB repository and development demo accounts.

## Required gaps under the revised baseline

| Area | Current state | Required change |
|---|---|---|
| Model–View–Presenter | Not compliant: shared FinanceController, concrete Api coupling and some View→API calls | Feature presenters, model/use-case interfaces, immutable states/effects and architecture tests |
| Country-neutral onboarding | Prototype defaults to MYR | Require explicit currency selection; remove assumed country context |
| Financial helper | Not implemented | Gross/net profile, debt schedules, DSR/DTI rules, scenarios and snapshots |
| Guilt-free wishlist | Not implemented | Items, funded reservations, readiness, forecast dates, purchase links and reversal flows |
| Cash/obligation model | Not implemented | Reconciled liquid snapshot, planning horizon, commitment occurrences and no-double-counting rules |
| Savings/emergency reserves | Not implemented | Goals and protected funded allocations |
| Atomic funding | Not implemented; current Compose uses standalone MongoDB | Transaction-capable MongoDB/atomic design, revisions and idempotency |
| Account completeness | No password reset/profile editing/data export | Complete R1 account/privacy requirements and new-entity deletion |
| Offline support | Not implemented | Cache, transaction queue, stable operation IDs and conflict resolution |
| Accessibility/performance | Basic responsive tests only | 200% text/device/screen-reader/performance acceptance checks |
| Production readiness | Local development only | HTTPS, encrypted storage, secrets, backups, distributed limits and monitoring |

Additional remaining items: category icon/color UI, recurring planning, monthly review additions and the R2/later features listed in the requirements. Existing transaction totals must not be used as verified cash to simulate a completed wishlist feature.

## Compatibility

Original requirement: Android 8+ and iOS 13+. Generated iOS target: 15.0. Android follows the installed Flutter SDK minimum. This discrepancy is unresolved; the project has not established its native release support matrix.

## Existing validation, before the architecture migration

- 19 backend tests passed; 94.34% statement coverage for the existing backend only.
- 6 Flutter tests passed; analysis was clean; web build succeeded.
- Phone/desktop dashboard renders inspected; local API/web HTTP availability checked.
- No live browser automation surface was available.
- Native device builds and real MongoDB integration were not verified.

These results do not cover DSR/DTI, wishlist, reservations, MVP presenter boundaries or new R1 requirements. See [TESTING.md](TESTING.md) for previous commands and new required acceptance suites.
