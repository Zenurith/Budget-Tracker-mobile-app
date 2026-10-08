# Implementation status

## Database encryption implementation on 2026-10-08

- AES-256-GCM document encryption is implemented for SQLite and Supabase through a backend repository decorator. Backend calculations and authorized exports receive decrypted data. IDs, ownership, login email, budget period and category lookup fields remain readable for existing queries/indexes.
- Normal application startup now requires a persistent `DOCUMENT_ENCRYPTION_KEY_FILE`. Keys are never generated implicitly; missing keys, plaintext legacy records and failed authentication do not fall back to plaintext. Existing environments need the setup/migration in [ENCRYPTION.md](ENCRYPTION.md) before restarting this version.
- Added an offline atomic migration/rotation command, read-only Docker secret mounting and security tests. Local backend suite: **243 passed, 8 opt-in live tests skipped**. Live Supabase encryption and migration have **not** been run; no live records, existing secrets or deployment configuration were changed by this implementation.
- This does not implement HTTPS deployment, mobile cache encryption, encrypted user exports, KMS integration or secure erasure of historical plaintext backups/WAL.

Updated 2026-10-05. The tracking prototype now uses feature presenters and a layered backend. Name editing and personal-data JSON export are implemented. Financial profiles, debt schedules and recurring commitments are implemented. DSR/DTI calculations, scenarios, personal ratio targets and saved snapshots are implemented. Protected funding and the guilt-free wishlist are implemented.

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

Planning is saved as owner-scoped `collection = planning` documents in the existing **pocketwise.documents** table, not new public tables. Export and account deletion include planning. No real-user sample data is inserted. The financial helper uses these inputs for DSR/DTI. Protected funding provides reconciled cash availability; wishlist readiness uses these reconciled cash inputs.

## Financial helper now available

**Settings → Financial plan → Open financial helper** shows debt ratios, normalized income/debt arithmetic, separate gross/net availability, income after debt, review age and optional personal targets. What-if calculations accept monthly income overrides, per-debt monthly replacements, an additional payment and an effective date. They never change real financial records. Reads and previews never save snapshots.

Named snapshots preserve the formula version, exact declared inputs, decimal outputs, date, source revision and assumptions on explicit save. They are stored as owner-scoped `calculation_snapshots` documents in the existing private table, included in export/deletion, and marked outdated using a profile/debt fingerprint. Payment links and ordinary expenses do not change that fingerprint. Saves are atomic and idempotent; stale revisions conflict. History is paginated in the API/UI (the current repository retrieves an owner's history before slicing it).

Reports includes ratios based on currently declared schedules at the selected month's end, or today for the current month. Past/future calculations explicitly state that they are not historical income records or guaranteed forecasts. Variable income continues to use explicit monthly estimates; automatic historical averaging is future work. Gemini remains inactive.

## Protected funding now available

**Settings → Financial plan → Open protected funding** supports named-account cash reconciliation, the confirmed-income-date/30-day horizon, linked essential allowances, buffers, future surplus, emergency/savings goals and explicit reserve/release/reallocation actions. Outside-account savings are recorded separately. Dated required reserves move from unfunded obligations into funded savings without double counting. See [FUNDING.md](FUNDING.md).

Cash and planning changes invalidate reviewed inputs. Ordinary expense recording remains available and marks cash for reconciliation. All funding mutations use the same owner transaction lock as transaction/payment writes, with an append-only reservation event ledger, revision checks and idempotent retries. Funding/events live in the existing private document table and are included in export/deletion; no migration is needed. Wishlist allocations, readiness, forecasts, purchases, refunds and link corrections are implemented; see [WISHLIST.md](WISHLIST.md).

## Guilt-free wishlist now available

**Protected funding → Open guilt-free wishlist** supports item lifecycle, priority, total cost, notes/reference URLs, explicit reservations, readiness reasons and monthly contribution forecasts. Paused/archived items keep their reservations. Forecast contributions never become available cash.

Actual purchase recording supports deduction from a reviewed prior snapshot or linking/creating an expense already included in reconciled cash. Purchases consume reservations atomically and preserve an idempotent audit record. Refunds record separate income; link corrections keep the original actual entries and require reconciliation. Reports include current reserves and monthly purchases/refunds; export/deletion includes wishlist records. See [WISHLIST.md](WISHLIST.md).

## Offline records now available

Recent transaction pages, categories, budgets and report snapshots remain readable with visible cache times when offline. Ordinary transaction creates/edits/deletes are durably queued with stable IDs; server version conflicts require explicit review. **Settings → Offline & sync** shows pending changes separately from totals and permits retry, review and conflict resolution. Session reauthentication preserves queued work. Pending transactions block protected-funding operations until resolved. See [OFFLINE.md](OFFLINE.md).

## Required gaps under the revised baseline

| Area | Current state | Required change |
|---|---|---|
| Model–View–Presenter | Feature presenters, repository interfaces and client dependency tests implemented | Preserve backend dependency gates and expand widget state coverage as new features arrive |
| Country-neutral onboarding | Explicit currency required for registration and demo in UI/API; no default selection | Preserve this requirement in future profile and financial flows |
| Financial helper | DSR/DTI, arithmetic explanations, personal targets, scenarios, saved snapshots and report ratios implemented | Optional Gemini explanations; native journey verification |
| Guilt-free wishlist | Items, reservations, readiness, forecasts, purchases, refunds and link corrections implemented | Native end-to-end acceptance |
| Cash/obligation model | Reconciled liquid snapshot, horizon, linked allowances, partial-payment obligations and cash invalidation implemented | Preserve purchase reconciliation guards |
| Savings/emergency reserves | Inside/outside goals, dated required reserves and reserve/release/reallocation implemented | Recurring savings automation |
| Atomic funding | Owner transactions, event ledger, revision checks, retries and live concurrency/rollback verified | Native journey verification |
| Account completeness | Name editing and personal-data JSON export implemented; password reset deferred by user on 2026-09-30 | Resume account recovery when requested; extend export/deletion when new entities arrive |
| Offline support | Recent cached records, durable transaction create/edit/delete queue, version conflicts and retry-safe replay implemented | Native restart/secure-storage acceptance; see [OFFLINE.md](OFFLINE.md) |
| Accessibility/performance | Primary pages tested at 200% phone text; chart amount tables/semantics and improved text contrast | Full-app/device/screen-reader/performance acceptance checks |
| Production readiness | Local development only | HTTPS, encrypted storage, secrets, backups, distributed limits and monitoring |

Monthly review now includes current reserves and recorded wishlist purchase/refund totals. Remaining items include the R2/later features listed in the requirements. Existing transaction totals must not be used as verified cash to simulate a completed wishlist feature.

## Compatibility

Original requirement: Android 8+ and iOS 13+. Generated iOS target: 15.0. Android follows the installed Flutter SDK minimum. This discrepancy is unresolved; the project has not established its native release support matrix.

## Dashboard and accessibility validation on 2026-10-06 (macOS)

- Dashboard now includes declared DSR/DTI and current wishlist progress, with missing-data, stale-data and current-versus-historical labels. Active target funding excludes paused items while total reservations retain their funds.
- Charts provide expandable category, monthly and daily amounts and semantic descriptions. Dashboard and primary-page overflow at 200% phone text was corrected; secondary text contrast was increased.
- Backend: **131 passed, 7 opt-in live tests skipped**, **94.52% coverage**. Flutter: **81 passed**; analysis clean. Phone/desktop dashboard goldens were updated and visually inspected. Windows goldens were not regenerated.
- Android debug APK and iOS simulator debug builds succeeded. Builds do not establish runtime journeys, release signing or supported-device compatibility. Screen-reader usability, native restart/secure-storage journeys and performance benchmarks remain unverified.
- Android emits a future Flutter compatibility warning for the Kotlin Gradle Plugin; migration to built-in Kotlin remains pending.

## Offline synchronization validation on 2026-10-05 (macOS)

- Backend: **130 passed, 7 opt-in live tests skipped locally**, **94.51% coverage**. Sync tests verify version conflicts, ownership, linked-record guards, replay after deletion, export exclusion, account cleanup and atomic rollback/concurrent retries.
- New live Supabase transaction-sync test: **1 passed** using two independent pools. Verified one transaction per retry ID, one winner for conflicting edits, and rollback of transaction, cash marker and replay record. Temporary records were cleaned up. The six previously passing integration tests were not rerun for this slice.
- Flutter: **78 passed**; plain Dart: **43 passed**. New coverage includes cache age/restart, lost-response replay, conflict review, storage failure before transmission, account isolation, expired-session reauthentication, pending-data export, sign-out cleanup, late reads, duplicate sync prevention and conflict confirmation at 200% phone text. Dashboard goldens passed unchanged.
- Web release build and Wasm compatibility dry run succeeded. Native secure-store/restart/device journeys, full accessibility, performance/NLP benchmarks and production operations remain unverified. See [OFFLINE.md](OFFLINE.md).

## Wishlist validation on 2026-10-05 (macOS)

- Live Supabase: **all 6 integration tests passed**, including wishlist purchase retries across independent pools, competing reservations/purchases and rollback after purchase/refund/link-correction writes. Temporary records were cleaned up; no migration was required. Read-only inspection confirmed RLS and no schema/table privileges for `anon` or `authenticated`.
- Backend: **127 passed, 6 opt-in live tests skipped locally**, **94.34% coverage**. Wishlist tests cover savings-only readiness, shortfalls, paused funds, forecasts, stale quotes, actual costs, reconciled existing/missing expenses, retry deduplication, refunds, link correction, ownership/currency, export/deletion and monthly reporting. Funding tests cover partial bills, outside-account savings and exclusion of future income; together these exercise WL-01–WL-14.
- Flutter: **66 passed**; plain Dart: **41 passed**; analysis clean. Includes purchase confirmations, stable retry keys, logout suppression, failed refresh after commit, 200% phone text, complete wishlist reloads after funding edits and existing-expense pagination. Dashboard goldens passed unchanged.
- Web release build and Wasm compatibility dry run succeeded. `git diff --check` passed. Native builds/device journeys, full screen-reader coverage and production performance remain unverified.

## Previous validation on 2026-10-02 (macOS)

- Backend: **118 passed, 5 opt-in live tests skipped locally**, **94.55% coverage**. Funding tests cover cash/forecast separation, missing versus zero, explicit confirmations, linked allowances, partial bill reconciliation, required reserves, outside savings, allocation/release/reallocation, stale data/revisions, goal guards, ownership/currency, retries, history, export/deletion and rollback.
- Live Supabase: **all 5 integration tests passed**. The funding test verifies persistence across two pools, same-key concurrent retries, competing allocations, event/aggregate rollback, expense/cash-marker rollback and allocation racing with an expense. Existing payment, helper and account integration checks also pass. Temporary records were cleaned up; no migration was needed.
- Flutter: **56 passed**; plain Dart: **35 passed**; analysis clean. Funding tests cover immutable state, late reads after sign-out/disposal, stale data, currency/revision forwarding, retry keys, duplicate submissions, failed refresh after a committed allocation, explicit cash/plan confirmation and a phone at 200% text. Existing dashboard goldens remain unchanged.
- Web release build and Wasm compatibility dry run succeeded. Native builds, physical-device journeys, full screen-reader coverage and production performance remain unverified. These tests do not validate the future wishlist purchase/reversal flows.

## Previous validation on 2026-10-01 (macOS)

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

The September results cover tracking and planning inputs; October adds the financial helper and protected funding. Wishlist checks are recorded in the October 5 validation; other remaining R1 requirements are not validated. See [TESTING.md](TESTING.md) for commands and required acceptance suites.
