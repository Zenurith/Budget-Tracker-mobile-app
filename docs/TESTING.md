# Testing and verification

## Commands

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

These checks do not validate the unimplemented financial helper, wishlist or protected-funding model.

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

- All FH-01–FH-12 cases in [FINANCIAL_HELPER.md](FINANCIAL_HELPER.md), including exact arithmetic, incomplete data, zero income, frequency conversion and scenario isolation.
- All WL-01–WL-14 cases in [WISHLIST.md](WISHLIST.md), including savings-only readiness, no double allocation, freshness, purchase retries and existing-expense reconciliation.
- Extend the implemented client MVP and backend dependency/domain checks in [ARCHITECTURE.md](ARCHITECTURE.md) to new features.
- Real MongoDB transaction/concurrency/rollback tests, API contract fixtures and owner isolation across every new collection.
- Extend the implemented explicit-currency onboarding checks to future profile editing and mixed-currency financial calculation rejection.
- Offline queue/conflict behavior, user-data export/deletion, accessibility, supported-device journeys and measured performance.

Documentation-only revisions validate links, requirement identifiers and cross-document consistency; rerunning prototype tests cannot validate features that have not been implemented.
