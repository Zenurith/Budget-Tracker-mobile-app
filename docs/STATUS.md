# Implementation status

Updated 2026-09-29. The tracking prototype now uses feature presenters and a layered backend. Release 1 financial helper, protected funding and wishlist remain specified but unimplemented.

## Architecture migration verified

- Auth, overview, transaction, budget and category presenters use injected repository interfaces, immutable state and typed change effects. The shared FinanceController has been removed.
- Views forward repository operations through presenters; dependency tests check that Views do not import API/storage adapters and presenters/models do not import Flutter.
- Presenter tests cover stale responses, logout during loading, immutable snapshots, duplicate submission, error/retry behavior and disposal.
- Backend boundaries are implemented and tested: API schemas map to immutable domain inputs; domain-owned repository/token/password protocols are injected; adapters translate duplicate-write errors; API handlers map semantic domain failures to HTTP. Domain imports are restricted to the standard library and domain modules.
- Registration and demo onboarding require explicit currency selection in the UI and API. Missing or unsupported currencies are rejected before creating account data; existing accounts keep their currency.

## Prototype capabilities already present

- Flutter Android/iOS/web project with responsive Material 3 screens.
- Registration/login, access/refresh JWTs, refresh rotation, sign-out and account/data deletion for existing entities.
- Transaction CRUD, monthly history, note/category search and type/category filtering; API also accepts amount/date filters and pagination.
- Default categories and custom creation/rename/delete; backend icon/color fields.
- Monthly overall/category budgets and on-screen threshold alerts.
- Recorded balance, income/expenses, recent activity, category donut, monthly comparison and daily trend charts.
- Local English transaction parsing with review/confirmation before saving; no external AI calls, even when a Gemini key is configured. Gemini is reserved for the planned financial helper and guilt-free wishlist; neither feature is implemented yet.
- Persistent SQLite development repository, a MongoDB repository and development demo accounts.

## Required gaps under the revised baseline

| Area | Current state | Required change |
|---|---|---|
| Model–View–Presenter | Feature presenters, repository interfaces and client dependency tests implemented | Preserve backend dependency gates and expand widget state coverage as new features arrive |
| Country-neutral onboarding | Explicit currency required for registration and demo in UI/API; no default selection | Preserve this requirement in future profile and financial flows |
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

## Current validation on 2026-09-29 (macOS)

- 64 backend tests passed, including unused Gemini adapter validation and local-only transaction preview/save behavior. The earlier 47-test baseline had 96.61% statement coverage; coverage has not been remeasured for Gemini.
- 18 Flutter tests passed; analysis was clean. Ten presenter/architecture tests also passed using plain Dart.
- Flutter web release build succeeded, including the Wasm compatibility dry run.
- Existing phone/desktop golden comparisons passed without baseline changes; earlier Windows baselines remain available.
- Live browser interaction was not rerun during this cleanup.
- Native device builds and real MongoDB integration were not verified.

These results cover existing tracking behavior and client presenter boundaries, not DSR/DTI, wishlist, reservations or the remaining R1 requirements. See [TESTING.md](TESTING.md) for commands and required acceptance suites.
