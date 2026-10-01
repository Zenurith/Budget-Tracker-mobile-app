# Implementation status

Updated 2026-10-01. The tracking prototype now uses feature presenters and a layered backend. Name editing and personal-data JSON export are implemented. Financial profiles, debt schedules and recurring commitments are implemented. DSR/DTI calculations, scenarios, personal ratio targets and saved snapshots are implemented. Protected funding and wishlist remain unimplemented.

## Architecture migration verified

- Auth, overview, transaction, budget and category presenters use injected repository interfaces, immutable state and typed change effects. The shared FinanceController has been removed.
- Views forward repository operations through presenters; dependency tests check that Views do not import API/storage adapters and presenters/models do not import Flutter.
- Presenter tests cover stale responses, logout during loading, immutable snapshots, duplicate submission, error/retry behavior and disposal.
- Backend boundaries are implemented and tested: API schemas map to immutable domain inputs; domain-owned repository/token/password protocols are injected; adapters translate duplicate-write errors; API handlers map semantic domain failures to HTTP. Domain imports are restricted to the standard library and domain modules.
- Registration and demo onboarding require explicit currency selection in the UI and API. Missing or unsupported currencies are rejected before creating account data; existing accounts keep their currency.

## Prototype capabilities already present

- Flutter Android/iOS/web project with responsive Material 3 screens.
- Registration/login, access/refresh JWTs, refresh rotation, sign-out and account/data deletion for existing entities.
- Settings supports editing the account name and saving a JSON export of the profile, all transactions, budgets and category definitions. Currency remains fixed. Export is owner-scoped and excludes password hashes and sessions; the response disables caching.
- Transaction CRUD and paginated history with combined note/category search, type/category, inclusive date-range and exact amount filters. Date ranges can span months. Loading, error/retry, empty states and explicit load-more are implemented; stale responses cannot replace newer filters or sign-out.
- Default categories and custom creation/edit/delete, including icon/color controls. Defaults remain read-only and used categories retain reference safeguards.
- Monthly overall/category budgets and on-screen threshold alerts.
- Recorded balance, income/expenses, recent activity, category donut, monthly comparison and daily trend charts.
- Reports include a monthly review of recorded income/spending/net change, previous-month spending difference and separate overall/category budget variances. Current/future/ended periods are labelled; recorded-day counts do not claim complete financial coverage.
- Local English transaction parsing with review/confirmation before saving; no external AI calls, even when a Gemini key is configured. Gemini remains reserved for later explanations and the guilt-free wishlist; the financial helper now uses deterministic calculations and templated explanations.
- Persistent SQLite development repository, a Supabase Postgres repository and development demo accounts.

## Financial planning now available

Open **Settings → Financial plan**, or the planning link under Budgets. Enter separately declared gross/net income, currency-matched sources, an explicit timezone and debt-list confirmation. Variable income supports an explicit monthly estimate with notes; automatic historical averaging remains future work. Unknown inputs remain distinct from zero. Review becomes due after 30 days, and changing debts invalidates confirmation.

Debt and recurring-bill schedules generate a monthly agenda with month-end/leap-year handling and partial/paid/overdue states. Record an already-made payment or select an existing expense; retries cannot create a duplicate expense. Unlink before editing/deleting a linked expense. Schedule terms with linked history are protected; close the schedule and create a replacement when terms change. Reads never automatically post expenses.

Planning is saved as owner-scoped `collection = planning` documents in the existing **pocketwise.documents** table, not new public tables. Export and account deletion include planning. No real-user sample data is inserted. The financial helper uses these inputs for DSR/DTI. Cash availability and wishlist results remain unimplemented.

## Financial helper now available

**Settings → Financial plan → Open financial helper** shows debt ratios, normalized income/debt arithmetic, separate gross/net availability, income after debt, review age and optional personal targets. What-if calculations accept monthly income overrides, per-debt monthly replacements, an additional payment and an effective date. They never change real financial records. Reads and previews never save snapshots.

Named snapshots preserve the formula version, exact declared inputs, decimal outputs, date, source revision and assumptions on explicit save. They are stored as owner-scoped `calculation_snapshots` documents in the existing private table, included in export/deletion, and marked outdated using a profile/debt fingerprint. Payment links and ordinary expenses do not change that fingerprint. Saves are atomic and idempotent; stale revisions conflict. History is paginated in the API/UI (the current repository retrieves an owner's history before slicing it).

Reports includes ratios based on currently declared schedules at the selected month's end, or today for the current month. Past/future calculations explicitly state that they are not historical income records or guaranteed forecasts. Variable income continues to use explicit monthly estimates; automatic historical averaging is future work. Gemini remains inactive.

## Required gaps under the revised baseline

| Area | Current state | Required change |
|---|---|---|
| Model–View–Presenter | Feature presenters, repository interfaces and client dependency tests implemented | Preserve backend dependency gates and expand widget state coverage as new features arrive |
| Country-neutral onboarding | Explicit currency required for registration and demo in UI/API; no default selection | Preserve this requirement in future profile and financial flows |
| Financial helper | DSR/DTI, arithmetic explanations, personal targets, scenarios, saved snapshots and report ratios implemented | Optional Gemini explanations; native journey verification |
| Guilt-free wishlist | Not implemented | Items, funded reservations, readiness, forecast dates, purchase links and reversal flows |
| Cash/obligation model | Scheduled occurrences and partial/full payment links implemented | Reconciled liquid snapshot, funding horizon and protected allocations |
| Savings/emergency reserves | Not implemented | Goals and protected funded allocations |
| Atomic funding | Payment transactions, revisions and idempotency implemented; funding not implemented | Reservation/funding invariants and concurrency |
| Account completeness | Name editing and personal-data JSON export implemented; password reset deferred by user on 2026-09-30 | Resume account recovery when requested; extend export/deletion when new entities arrive |
| Offline support | Not implemented | Cache, transaction queue, stable operation IDs and conflict resolution |
| Accessibility/performance | Basic responsive tests only | 200% text/device/screen-reader/performance acceptance checks |
| Production readiness | Local development only | HTTPS, encrypted storage, secrets, backups, distributed limits and monitoring |

Additional remaining items: goal/wishlist monthly-review sections, and the R2/later features listed in the requirements. Existing transaction totals must not be used as verified cash to simulate a completed wishlist feature.

## Compatibility

Original requirement: Android 8+ and iOS 13+. Generated iOS target: 15.0. Android follows the installed Flutter SDK minimum. This discrepancy is unresolved; the project has not established its native release support matrix.

## Current validation on 2026-10-01 (macOS)

- Backend: **107 passed, 4 opt-in live tests skipped locally**, **93.97% coverage**. New coverage includes all FH-01–FH-12, half-up rounding, personal targets, report dates, input immutability, source revisions, snapshot pagination/export/deletion, ownership, retries and rollback.
- New live Supabase snapshot test: **1 passed** against the configured development project. Verified cross-connection persistence, concurrent same-key retries, owner isolation and rollback after a write. Temporary users/plans/snapshots were cleaned up. No schema migration was required.
- Flutter: **47 passed**; plain Dart: **29 passed**; analysis clean. Helper/widget/presenter checks include scenario preview/save, missing-input and error/retry states, logout/disposal, immutable state, stale-response ordering and phone layout at 200% text.
- Web release build and Wasm compatibility dry run succeeded. Native builds and device journeys remain unverified.

## Previous validation on 2026-09-30 (macOS)

- Backend local suite: 90 tests passed, 92.93% statement coverage; the 3 opt-in live tests skip locally. All 3 live Supabase tests passed separately, including real payment rollback, same-key concurrent retries and competing revision checks.
- Flutter: 37 tests passed, including financial-profile entry and confirmed partial payments, with unchanged dashboard goldens. Twenty-two presenter/dependency tests passed with plain Dart. Analysis is clean.
- Web release build and Wasm compatibility dry run succeeded.
- Supabase connection verified for project `icgbteadskymmrrqqyiq`; the missing private-schema migration was applied. RLS is enabled, required indexes exist, and `anon`/`authenticated` have no schema/table access. Repository tests verify persistence across connections, ownership filters, category/overall-budget uniqueness and concurrent single-use session consumption. API tests verify cross-owner read/update/delete restrictions, persisted name/export data across API instances, account deletion and cleanup of temporary test records.
- `backend/.env` is configured for Supabase mode with a stable JWT secret. MCP authentication is configured, but tools were unavailable in this session; verification used the application's Postgres connection. Multi-record funding transactions remain unimplemented.
- A fresh app instance loaded the configured environment, started successfully and reported `{"status":"ok","storage":"supabase"}`. The new table contained zero documents after integration cleanup. Existing SQLite data was not migrated.
- Native file-save dialogs and native builds have not been verified. Web downloads are wired through the file-picker adapter; browser interaction was not rerun.

## Previous validation on 2026-09-29 (macOS)

- 64 backend tests passed, including unused Gemini adapter validation and local-only transaction preview/save behavior. The earlier 47-test baseline had 96.61% statement coverage; coverage has not been remeasured for Gemini.
- 18 Flutter tests passed; analysis was clean. Ten presenter/architecture tests also passed using plain Dart.
- Flutter web release build succeeded, including the Wasm compatibility dry run.
- Existing phone/desktop golden comparisons passed without baseline changes; earlier Windows baselines remain available.
- Live browser interaction was not rerun during this cleanup.
- Native device builds and real Supabase Postgres integration were not verified.

The September results cover tracking and planning inputs; the October results add the financial helper. Wishlist, reservations and other remaining R1 requirements are not validated. See [TESTING.md](TESTING.md) for commands and required acceptance suites.
