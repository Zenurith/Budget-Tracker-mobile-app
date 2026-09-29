# Pocketwise

A personal budget tracker built with Flutter, FastAPI and MongoDB support. The revised [Release 1 requirements](skills_files/budget_tracker_requirements.md) require **Model–View–Presenter (MVP)** architecture, a country-neutral DSR/DTI financial helper and a guilt-free wishlist funded only by saved money.

The runnable tracking prototype now uses feature presenters with tested repository boundaries and a layered backend. The financial helper and wishlist are **specified but not implemented**; see [current status](docs/STATUS.md).

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

## MongoDB

With Docker Compose installed, set `JWT_SECRET` to a random value of at least 32 characters and run:

```sh
export JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
docker compose up --build
```

The Compose database is exposed on `127.0.0.1:27017` for local tools and persists in a named volume. This is a development setup, without production TLS or MongoDB authentication. Demo creation is disabled in MongoDB mode; create a real account instead.

To inspect it in MongoDB Compass, choose **Add New Connection**, enter `mongodb://127.0.0.1:27017`, name the connection **Pocketwise local**, and select **Save & Connect**. No database username/password is required for this local configuration. The API creates the `pocketwise` collections and indexes at startup; register in the app and add a transaction to see your data. The API container continues to use `mongodb://mongo:27017` internally.

Stop any separately running API before starting Compose to free port 8000. Check `http://localhost:8000/health` for `{"status":"ok","storage":"mongo"}`. Keep the same `JWT_SECRET` across restarts to preserve sessions. Existing SQLite data is not automatically copied to MongoDB.

Alternatively, set `DATABASE_MODE=mongo`, `MONGODB_URI`, `MONGODB_DATABASE`, and `JWT_SECRET` in `backend/.env` and run the API directly.

API documentation: http://localhost:8000/docs

## Project guide

- [Product requirements](skills_files/budget_tracker_requirements.md)
- [Model–View–Presenter architecture](docs/ARCHITECTURE.md)
- [Financial helper: DSR and DTI](docs/FINANCIAL_HELPER.md)
- [Guilt-free wishlist rules](docs/WISHLIST.md)
- [Target data and API contracts](docs/DATA_AND_API.md)
- [Confirmed decisions and open choices](docs/DECISIONS.md)
- [Implementation plan and acceptance scenarios](docs/PLAN.md)
- [Implemented features and remaining work](docs/STATUS.md)
- [Testing and verification](docs/TESTING.md)

The original Java starter remains untouched. The app lives in `mobile/` and `backend/`. This is a working prototype; new financial features, broader UI state coverage and remaining release work are tracked in the status document. Registration and demo onboarding require an explicit currency choice in both the UI and API (EUR, GBP, MYR, SGD or USD).

## Planned Gemini features

Gemini (`gemini-3.5-flash-lite`) is reserved for the financial helper and guilt-free wishlist. Keep `GEMINI_API_KEY` in `backend/.env`; `GEMINI_MODEL` records the intended model. These settings do not activate any AI feature yet. Transaction entry always uses local rules, even when a key is configured.

The planned design uses Python for DSR/DTI, savings, commitments and purchase-readiness calculations, with Gemini explaining the results and answering questions. Both features remain unimplemented. The unused Gemini adapter is retained as a transport/validation reference and will need feature-specific prompts and schemas.
