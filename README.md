# Pocketwise

A personal budget tracker built with Flutter, FastAPI and Supabase Postgres support. The revised [Release 1 requirements](skills_files/budget_tracker_requirements.md) require **Model–View–Presenter (MVP)** architecture, a country-neutral DSR/DTI financial helper and a guilt-free wishlist funded only by saved money.

The runnable tracking prototype now uses feature presenters with tested repository boundaries and a layered backend. Financial profiles, debts, recurring bills and the financial helper are available through **Settings → Financial plan** (also linked from Budgets). The financial helper now provides DSR/DTI calculations, what-if comparisons and explicitly saved snapshots. Protected funding, the guilt-free wishlist and basic offline transaction synchronization are implemented; see [current status](docs/STATUS.md).

## Run locally

Python 3.11+ and Flutter are required. Add your Flutter SDK's `bin` directory to PATH.

Start the API in one terminal:

```sh
cd backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
cp -n .env.example .env
# Optional: set JWT_SECRET in .env to preserve sessions across server restarts.
.venv/bin/uvicorn app.main:app --reload --env-file .env --host 127.0.0.1 --port 8000
```

Start Flutter in another:

```sh
cd mobile
flutter pub get
flutter run -d chrome --web-port 5173
```

For the API on Windows PowerShell, use:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --env-file .env --host 127.0.0.1 --port 8000
```

Use **Try the demo** and select a currency for a fresh sample account, or create an account for your own transactions. Local data persists in `backend/data/pocketwise.sqlite`. Demo accounts are separate and are created only when requested. Natural-language transaction entry always uses the local rules parser and makes no external AI calls.

For Android emulator development, `flutter run` defaults to API host `10.0.2.2:8000`. iOS simulator and web default to `localhost:8000`.

To run on an Android emulator, start the API above, open the `mobile/` folder
as the Flutter project in your IDE, and start your emulator from Device Manager.
From a terminal in `mobile/`, run:

```powershell
flutter pub get
flutter devices
flutter run -d emulator-5554
```

Use the emulator ID printed by `flutter devices` if it differs. The repository
root contains a separate Java starter; the Flutter entry point is
`mobile/lib/main.dart`. Keep the API terminal running for sign-in and demo mode.

For a physical device, override the API address:

```sh
flutter run --dart-define=API_URL=http://YOUR_LAN_IP:8000
```

Bind the development API to `0.0.0.0` when using a physical device. Release builds should use HTTPS. Browser CORS defaults permit port 5173; update `CORS_ORIGINS` for other origins.

## Supabase

1. Create a Supabase project and run [`supabase/migrations/202609300001_documents.sql`](supabase/migrations/202609300001_documents.sql) once in its SQL Editor.
2. Under **Connect**, copy the **Session pooler** Postgres URI (port 5432). Replace the password placeholder with your URL-encoded database password.
3. Set these values in `backend/.env`:

```dotenv
DATABASE_MODE=supabase
SUPABASE_DB_URL=postgresql://postgres.PROJECT_REF:ENCODED_PASSWORD@POOLER_HOST:5432/postgres
JWT_SECRET=YOUR_RANDOM_SECRET_AT_LEAST_32_CHARACTERS
```

Generate the JWT secret using the command in `.env.example`. Install the updated backend requirements and start the API using the local instructions above. Or, from the repository root, run:

```sh
docker compose --env-file backend/.env up --build
```

Compose runs the API against hosted Supabase; it no longer starts MongoDB. Check `http://localhost:8000/health` for `{"status":"ok","storage":"supabase"}`. This endpoint reports configuration, not a continuous database connectivity probe. Stop any separately running API first to free port 8000.

The backend uses a TLS Postgres connection and a small connection pool. See [Supabase's connection guide](https://supabase.com/docs/guides/database/connecting-to-postgres). Keep the database URI on the backend only. It is a database credential, not a publishable or service-role API key.

FastAPI still handles login, password hashing, JWT sessions and user ownership. Supabase Auth is not enabled. The current document repository maps to JSONB records in the private `pocketwise.documents` table, with unique email/budget indexes and atomic session consumption. The migration restricts `anon`/`authenticated` access and enables RLS without client policies; connect as the database owner through the backend. Do not expose this schema through the Data API. Funding now uses an owner aggregate and reservation event documents in atomic Postgres transactions. Wishlist purchases, refunds and link corrections use the same atomic owner transaction. Dedicated relational tables remain future work.

Demo creation is available only in local SQLite mode. Existing SQLite/MongoDB records are **not automatically migrated**. Switching back to `DATABASE_MODE=local` retains your existing SQLite data. Keep the same `JWT_SECRET` across restarts to preserve sessions.

API documentation: http://localhost:8000/docs

The Supabase Table Editor may initially show the empty `public` schema. Select **pocketwise** in its schema dropdown to see **documents**. The current prototype stores entity types as JSONB records distinguished by the `collection` column, rather than separate account/transaction/budget tables. This private schema is accessed through FastAPI; it is intentionally not exposed directly to client roles.

Transactions support combined search, type/category, date-range and amount filters with 50-record pages. Use **Date & amount** for ranges spanning multiple months, **Load more transactions** for the next page, or **Clear filters** to return to the selected month. Settings lets you choose icons and colors for custom categories. Reports includes a monthly spending/budget review and debt ratios from declared schedules, with incomplete-period and recording-coverage labels.

In **Settings**, use **Edit profile** to update your name or **Export my data** to save `pocketwise-data.json`. The export includes your profile, all transaction history, budgets and category definitions; recorded money amounts are integer minor units in your account currency. Financial calculation snapshots additionally preserve normalized fractional minor-unit amounts and percentages as decimal strings. Password hashes and authentication sessions are excluded. Browsers start a download; Android/iOS use a file-save dialog. Native export behavior still needs device verification. Password reset remains planned.

## Project guide

- [Product requirements](skills_files/budget_tracker_requirements.md)
- [Model–View–Presenter architecture](docs/ARCHITECTURE.md)
- [Financial helper: DSR and DTI](docs/FINANCIAL_HELPER.md)
- [Protected cash and savings](docs/FUNDING.md)
- [Guilt-free wishlist rules](docs/WISHLIST.md)
- [Offline records and sync](docs/OFFLINE.md)
- [Target data and API contracts](docs/DATA_AND_API.md)
- [Confirmed decisions and open choices](docs/DECISIONS.md)
- [Implementation plan and acceptance scenarios](docs/PLAN.md)
- [Implemented features and remaining work](docs/STATUS.md)
- [Testing and verification](docs/TESTING.md)

The original Java starter remains untouched. The app lives in `mobile/` and `backend/`. This is a working prototype; new financial features, broader UI state coverage and remaining release work are tracked in the status document. Registration and demo onboarding require an explicit currency choice in both the UI and API (EUR, GBP, MYR, SGD or USD).

## Financial helper

Open **Settings → Financial plan → Open financial helper**, or use its link in Reports. Review your gross/net income and debt list first. The helper shows net-basis DSR, gross-basis DTI, income after debt, itemized arithmetic and missing-input/review warnings. Optional personal percentage targets are entered when reviewing the financial profile; none are selected by default.

**Try a what-if scenario** can change the effective date, monthly income, individual required monthly payments or an additional hypothetical payment. Comparing and discarding never changes your real records. **Save baseline snapshot** and **Save scenario snapshot** explicitly preserve the calculation inputs, formula version and results. Saved snapshots appear below the results and are marked outdated after profile/debt changes. They are included in personal-data export and account deletion.

Snapshots use `collection = calculation_snapshots` in the existing private document table; no new SQL migration is needed. Snapshot saves use revision checks and idempotency keys inside the existing owner transaction. Normalization uses decimal arithmetic and percentages use half-up rounding to two decimals. Paying an occurrence or recording extra repayment does not reduce scheduled baseline debt. Essentials and savings have not been deducted from income after debt.

## Protected funding

Open **Settings → Financial plan → Open protected funding**. Reconcile actual included account balances, create emergency/savings goals, and review the horizon, remaining essential allowances, buffer and future surplus. Then explicitly reserve, release or move cash between goals. Expected income never becomes available cash; savings outside included accounts are not subtracted again.

Cash changes require reconciliation, and the funding plan must be reviewed on the current local date and after obligation/goal changes. Incomplete or stale inputs prevent contributions. Reservation changes are atomic and idempotent and appear in history. Funding and history are included in export/account deletion. See [the funding guide](docs/FUNDING.md) for allowance linking, required savings and concurrency rules. Wishlist readiness and purchase recording remain the next slice.

## Planned Gemini features

Gemini (`gemini-3.5-flash-lite`) is reserved for the financial helper and guilt-free wishlist. Keep `GEMINI_API_KEY` in `backend/.env`; `GEMINI_MODEL` records the intended model. These settings do not activate any AI feature yet. Transaction entry always uses local rules, even when a key is configured.

The planned design uses Python for DSR/DTI, savings, commitments and purchase-readiness calculations, with Gemini explaining the results and answering questions. The deterministic financial helper and wishlist are implemented; Gemini explanations remain unimplemented. The unused Gemini adapter is retained as a transport/validation reference and will need feature-specific prompts and schemas.
