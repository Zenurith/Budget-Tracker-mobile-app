# Testing and verification

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

## Protected funding checks on 2026-10-02 (macOS)

- Backend: **118 passed, 5 opt-in live tests skipped locally**, **94.55% coverage**. Funding tests cover cash/forecast separation, missing versus zero, explicit confirmations, linked allowances, partial bill reconciliation, required reserves, outside savings, allocation/release/reallocation, stale data/revisions, goal guards, ownership/currency, retries, history, export/deletion and rollback.
- Live Supabase: **all 5 integration tests passed**. The funding test verifies persistence across two pools, same-key concurrent retries, competing allocations, event/aggregate rollback, expense/cash-marker rollback and allocation racing with an expense. Existing payment, helper and account integration checks also pass. Temporary records were cleaned up; no migration was needed.
- Flutter: **56 passed**; plain Dart: **35 passed**; analysis clean. Funding tests cover immutable state, late reads after sign-out/disposal, stale data, currency/revision forwarding, retry keys, duplicate submissions, failed refresh after a committed allocation, explicit cash/plan confirmation and a phone at 200% text. Existing dashboard goldens remain unchanged.
- Web release build and Wasm compatibility dry run succeeded. Native builds, physical-device journeys, full screen-reader coverage and production performance remain unverified. These tests do not validate the future wishlist purchase/reversal flows.

## Financial helper checks on 2026-10-01 (macOS)

- Backend: **107 passed, 4 skipped**, **93.97% coverage**. All FH-01–FH-12 are covered, including partial availability, zero denominators, >100% ratios, required versus extra/paid amounts, normalization, currency/ownership, effective dates and scenario isolation. Additional tests cover half-up rounding, review age, targets, report dates, immutable snapshots, revision conflicts, explicit save, replay, pagination, export/deletion and rollback.
- New live Supabase snapshot test: **1 passed** (`-k helper_snapshot`). Verified persistence across pools, concurrent retry deduplication, owner isolation and rollback after an inserted snapshot. Temporary records were cleaned up. The other three existing live tests were not rerun for this slice.
- Flutter: **47 passed**; plain Dart: **29 passed**; analysis clean. Dashboard goldens are unchanged. Helper coverage includes input validation, incomplete results, reload races, sign-out/disposal, revision invalidation, duplicate submission and retry keys, scenario comparison/save, and a 390×844 phone at 200% text.
- Web release build and Wasm dry run succeeded. Native device builds/journeys, performance and full screen-reader checks remain unverified.

## Financial profile and commitments checks on 2026-09-30 (macOS)

- Backend: **90 passed, 3 skipped**, **92.93% coverage**. Tests cover missing versus zero income, explicit review, currency/timezone validation, recurrence dates, partial/existing payment links, owner isolation, stale revisions, retries and atomic rollback.
- Live Supabase: **3 passed**. The new test verifies rollback after an expense write and concurrency across independent connection pools: one expense for same-key retries, and one winner for conflicting revision writes. Temporary records are cleaned up.
- Flutter: **37 passed**; plain Dart: **22 passed**. Profile entry and confirmed partial-payment widgets, stable payment retry IDs, duplicate-click guards, stale-owner suppression and failed refresh after successful save are covered. Dashboard goldens remain unchanged. Analysis is clean.
- Native devices, full-app accessibility, DSR/DTI and protected funding are not verified by these tests.

## Core tracking completion checks on 2026-09-30 (macOS)

- Backend: **80 passed, 2 skipped**, **95.22%** coverage. The skips are the opt-in Supabase tests; both passed in a separate live run.
- Live Supabase now also checks category icon/color persistence, category-name searches, inclusive date/amount filtering across months, pagination and monthly review arithmetic. Temporary accounts and records are removed afterward.
- Flutter: **31 passed**; plain Dart: **18 passed** using `dart test test/presenter_test.dart test/account_presenter_test.dart test/history_presenter_test.dart`. Tests cover stale filter responses, sign-out while loading, paging/retry, category appearance selection, amount validation and the filter dialog at 200% text size. Existing dashboard goldens passed unchanged.
- Analysis is clean; web release build and Wasm compatibility dry run passed. `git diff --check` passed. Native device behavior and full-app 200% accessibility remain unverified.
- Password recovery is deferred by the user's request; the spending/budget review does not claim the later debt-ratio, savings or wishlist modules are implemented.

## Account editing and export verification on 2026-09-30 (macOS)

- Backend local suite: **78 passed**, **95.16%** coverage (live tests opt in separately). New tests cover own-name editing, protected-field rejection, persistence through login, export of more than one page of history, cross-owner exclusion, removal of credentials/session data and authentication after account deletion.
- Flutter: **25 tests passed**, including Settings editing/export, failure and retry, duplicate submissions, cancellation, disposal during export, token refresh for account endpoints and unchanged dashboard goldens.
- Plain Dart: **15 presenter/dependency tests passed** using `dart test test/presenter_test.dart test/account_presenter_test.dart`.
- Web release build and Wasm compatibility dry run succeeded. Native file-save dialogs remain unverified; the widget test uses a fake export destination.
- Live Supabase: **2 integration tests passed** against `icgbteadskymmrrqqyiq` after applying the previously missing migration. Checks cover cross-connection persistence, category and overall-budget uniqueness, concurrent single-use sessions, API owner isolation, name/export persistence across separate API instances and account deletion. Temporary accounts/records are cleaned up. Read-only inspection confirmed RLS, the expected indexes and denied schema/table privileges for `anon`/`authenticated`. This is not verification of multi-record funding transactions.
- Flutter analysis is clean. The file export uses `file_picker` 13.1.0, pinned with the resolved lockfile; native save dialogs still need device testing.
- A fresh app instance loaded `backend/.env`, initialized the real Supabase repository and returned `{"status":"ok","storage":"supabase"}` from `/health`. A final count found zero documents after test cleanup. Local SQLite records were not migrated.

## Test commands

Backend (from `backend/`):

```sh
.venv/bin/python -m pytest --cov=app --cov-report=term-missing --cov-fail-under=70 -q
```

On Windows, use `.\.venv\Scripts\python.exe` instead of `.venv/bin/python`.

Flutter (from `mobile/`, with Flutter on PATH):

```sh
flutter analyze
flutter test
flutter build web
```

Run the presenter and client dependency tests without Flutter using `dart test test/presenter_test.dart` from `mobile/`.

Golden image baselines use the bundled fonts at fixed phone and desktop sizes. After an intentional visual change, inspect the images before accepting updates:

```sh
flutter test --update-goldens test/dashboard_test.dart
```

Windows uses `mobile/test/goldens/windows/`; other platforms retain the original baselines in `mobile/test/goldens/`. This preserves platform rendering differences without relaxing pixel comparisons.

## Backend boundary cleanup verification on 2026-09-29 (macOS)

- Final backend suite: **47 tests passed**, **96.61%** statement coverage. Domain imports also succeeded with site packages disabled (`python -S`).

- Existing 40 API tests pass with the same public behavior after moving schemas to the API layer and mapping them to immutable domain inputs.
- Seven additional tests cover domain dependency restrictions, injected authentication adapters, single-use refresh tokens, missing-user dummy verification, registration races, transaction ownership/date serialization and SQLite/MongoDB duplicate-error translation.
- Domain code uses only the standard library and other domain modules; repositories and security implement domain-owned contracts. HTTP error mapping resides in the API layer.
- MongoDB duplicate translation uses a mocked driver collection; this does not verify a live MongoDB deployment. The existing Starlette TestClient deprecation warning remains.
- Flutter was not rerun for this backend-only refactor; the preceding 18 Flutter tests, 10 Dart checks, clean analysis and web build remain the latest client results.

## Explicit currency verification on 2026-09-29 (macOS)

- Backend: **40 tests passed**, **95.69%** statement coverage. Cases cover missing/invalid currencies with no writes, all five supported currencies through registration/demo and session refresh, required demo request bodies and the MongoDB-mode demo restriction (using a local test repository).
- Flutter analysis: no issues; **18 Flutter tests passed**, including demo picker cancellation/selection and adapter request payloads. Existing dashboard golden comparisons passed without changes.
- Plain Dart: **10 presenter/dependency tests passed**, including demo validation before repository access.
- Flutter web release build and Wasm compatibility dry run succeeded.
- Native builds and real MongoDB integration remain unverified. The existing Starlette TestClient deprecation warning remains.

## Merge cleanup verification on 2026-09-29 (macOS)

- Resolved committed conflict markers in five documentation files, `.gitignore`, `.idea/misc.xml` and `test.iml`; checked all tracked files for remaining markers.
- Validated the edited IDE XML, local README/documentation links and `git diff --check`.
- Backend: **19 tests passed**, **95.46%** statement coverage on Python 3.14.6. The existing Starlette TestClient deprecation warning remains.
- Flutter 3.47.5 / Dart 3.13.4: analysis reported no issues; **15 Flutter tests passed**, including the existing phone/desktop golden comparisons; **9 plain-Dart presenter/dependency tests passed**.
- Flutter dependency resolution updated six lockfile packages for the installed SDK: matcher, meta, test, test_api, test_core and vector_math. No pubspec constraints changed.
- Flutter web release build succeeded, including the Wasm compatibility dry run.
- Native builds and real MongoDB integration were not run.

## Presenter migration verification on 2026-09-28 (Windows)

- Backend: **19 tests passed**, **95.52%** statement coverage after extracting routes, domain, infrastructure and repositories.
- Flutter analysis: no issues; **15 tests passed**, including phone/desktop navigation and inspected Windows dashboard goldens.
- Plain Dart: **9 tests passed**, including dependency gates, explicit currency validation, stale response ordering, logout during loading, immutable state, duplicate submissions, disposal and error/retry behavior.
- Flutter web release build succeeded, including the Wasm compatibility dry run. Native builds remain unverified.
- At that revision, remaining migration work included backend auth infrastructure coupling, shared transport/domain request models and broader widget coverage. The backend boundaries were completed on 2026-09-29 (see above).

The historical checks below did not cover the financial helper; the October checks above do. Protected funding is covered by the October 2 suite; wishlist is covered by the October 5 suite.

## Prototype verification on 2026-09-28 (before the revised architecture/features)

- Backend: **19 tests passed**, **94.34%** statement coverage.
- Flutter analysis: no issues.
- Flutter: **6 tests passed**, covering input/auth/NLP confirmation/token rotation and phone/desktop navigation/layout checks.
- Flutter web release build succeeded.
- Local HTTP checks: API `/health` returned `ok`; the web preview returned HTTP 200.
- Rendered dashboard images inspected at 1440×1100 and 390×844 with real app fonts. Images are in `mobile/test/goldens/`.

Backend tests exercise token rotation and replay rejection, logout, account deletion, user isolation, transaction CRUD and filtering, exact integer totals, month boundaries, category safeguards, budget upserts, ambiguous parser inputs, explicit NLP confirmation semantics, demo setup, rate limiting, and persistent local storage. These parser cases are correctness examples, not an NLP accuracy benchmark.

Flutter tests cover exact conversion of money input to minor units, required sign-in fields, parsing without implicit saves, confirmation-triggered saving, automatic token refresh, and navigation at phone/desktop widths. Golden tests may vary slightly with Flutter/engine/platform versions; compare intentional changes visually.

## Not yet verified

- Live browser interaction: no browser control surface was available during the earlier prototype verification; browser interaction was not rerun during merge cleanup. The preview servers were reachable, and the app was checked using Flutter rendering/widget tests instead.
- Android/iOS builds, signing, emulator and physical-device behavior.
- MongoDB integration: the earlier prototype verification had no Docker or running MongoDB available; backend tests use the persistent local repository.
- Performance targets, screen-reader usability, large text, offline behavior, production TLS, backups, and all non-functional acceptance criteria.

A Starlette deprecation warning currently appears for its httpx-based TestClient. It does not fail the suite; review test-client dependency changes on the next dependency update.

## Required suites for the revised Release 1

The results above apply to existing tracking and presenter behavior. Remaining suites include:

- FH-01–FH-12 in [FINANCIAL_HELPER.md](FINANCIAL_HELPER.md) are covered by the October helper suite; preserve them as the funding and wishlist models are added.
- All WL-01–WL-14 cases in [WISHLIST.md](WISHLIST.md), including savings-only readiness, no double allocation, freshness, purchase retries and existing-expense reconciliation.
- Extend the implemented client MVP and backend dependency/domain checks in [ARCHITECTURE.md](ARCHITECTURE.md) to new features.
- Real Supabase Postgres transaction/concurrency/rollback tests, API contract fixtures and owner isolation across every new collection.
- Extend the implemented explicit-currency onboarding checks to future profile editing and mixed-currency financial calculation rejection.
- Offline queue/conflict behavior, user-data export/deletion, accessibility, supported-device journeys and measured performance.

Documentation-only revisions validate links, requirement identifiers and cross-document consistency; rerunning prototype tests cannot validate features that have not been implemented.


## Supabase migration verification

MongoDB has been replaced by a Supabase Postgres adapter; MongoDB results above are historical. Run the regular backend suite with `.venv/bin/python -m pytest -q` from `backend/`. Tests cover configuration errors, hosted demo restrictions and driver error translation alongside the existing local API/domain tests.

For live persistence verification, apply `supabase/migrations/202609300001_documents.sql` to a disposable Supabase project, set `TEST_SUPABASE_DB_URL` in the test process environment, then run `.venv/bin/python -m pytest -q tests/test_supabase_integration.py`. This test writes uniquely tagged records and cleans them up. It checks cross-connection persistence, update/delete behavior, ownership filters, unique email/budget constraints and concurrent single-use session consumption. It skips without the explicit test connection string. Never point it at production.

The local verification does not establish live Supabase connectivity or multi-record funding transaction correctness. Supabase Auth and migration of existing user data are outside this database adapter change.

Read-only connection/schema inspection is available via `backend/.venv/bin/python backend/scripts/check_supabase.py` from the repository root. It reads `backend/.env`, prints no credentials or user records, and does not apply migrations. The 2026-09-30 live results above establish connectivity for the configured project; future projects still need their own checks. When updating an already-migrated database, ensure the overall-budget unique index also treats null category IDs as equal (`NULLS NOT DISTINCT`).
