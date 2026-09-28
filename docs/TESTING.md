# Testing and verification

## Commands

Backend (from `backend/`):

```sh
.venv/bin/python -m pytest --cov=app --cov-report=term-missing --cov-fail-under=70 -q
```

Flutter (from `mobile/`, with Flutter on PATH):

```sh
flutter analyze
flutter test
flutter build web
```

Golden image baselines use the bundled fonts at fixed phone and desktop sizes. After an intentional visual change, inspect the images before accepting updates:

```sh
flutter test --update-goldens test/dashboard_test.dart
```

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

- Live browser interaction: no browser control surface was available in this session. The preview servers were reachable, and the app was checked using Flutter rendering/widget tests instead.
- Android/iOS builds, signing, emulator and physical-device behavior.
- MongoDB integration: this machine had no Docker or running MongoDB available; backend tests use the persistent local repository.
- Performance targets, screen-reader usability, large text, offline behavior, production TLS, backups, and all non-functional acceptance criteria.

A Starlette deprecation warning currently appears for its httpx-based TestClient. It does not fail the suite; review test-client dependency changes on the next dependency update.

## Required suites for the revised Release 1

The earlier results apply only to the existing prototype. The new suites are requirements, not implemented tests:

- All FH-01–FH-12 cases in [FINANCIAL_HELPER.md](FINANCIAL_HELPER.md), including exact arithmetic, incomplete data, zero income, frequency conversion and scenario isolation.
- All WL-01–WL-14 cases in [WISHLIST.md](WISHLIST.md), including savings-only readiness, no double allocation, freshness, purchase retries and existing-expense reconciliation.
- MVP dependency checks in [ARCHITECTURE.md](ARCHITECTURE.md): no View→API/storage calls; plain-Dart presenters and fakeable model interfaces.
- Real MongoDB transaction/concurrency/rollback tests, API contract fixtures and owner isolation across every new collection.
- Country-neutral onboarding and explicit currency selection; reject mixed-currency financial calculations.
- Offline queue/conflict behavior, user-data export/deletion, accessibility, supported-device journeys and measured performance.

Documentation-only revisions validate links, requirement identifiers and cross-document consistency; rerunning prototype tests cannot validate features that have not been implemented.
