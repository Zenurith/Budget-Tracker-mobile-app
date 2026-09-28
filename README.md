# Pocketwise

A personal budget tracker built with Flutter, FastAPI and MongoDB support. The revised [Release 1 requirements](skills_files/budget_tracker_requirements.md) require **Model–View–Presenter (MVP)** architecture, a country-neutral DSR/DTI financial helper and a guilt-free wishlist funded only by saved money.

The current runnable app is an earlier tracking prototype. The presenter refactor, financial helper and wishlist are **specified but not implemented**; see [current status](docs/STATUS.md).

## Run locally

Python 3.11+ and Flutter are required. On this machine Flutter is installed at `/Users/zactan/develop/flutter/bin/flutter`; add that directory to PATH or use the full path below.

Start the API in one terminal:

```sh
cd backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
cp .env.example .env
# Optional: set JWT_SECRET in .env to preserve sessions across server restarts.
.venv/bin/uvicorn app.main:app --reload --env-file .env --host 127.0.0.1 --port 8000
```

Start Flutter in another:

```sh
cd mobile
/Users/zactan/develop/flutter/bin/flutter pub get
/Users/zactan/develop/flutter/bin/flutter run -d chrome --web-port 5173
```

Use **Try the demo** for a fresh sample account, or create an account for your own transactions. Local data persists in `backend/data/pocketwise.sqlite`. Demo accounts are separate and are created only when requested. The local parser makes no external AI calls.

For Android emulator development, `flutter run` defaults to API host `10.0.2.2:8000`. iOS simulator and web default to `localhost:8000`. A physical device needs an API URL reachable on your network:

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

The Compose database is isolated from host ports and persists in a named volume. This is a development setup, without production TLS or MongoDB authentication. Demo creation is disabled in MongoDB mode; create a real account instead.

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

The original Java starter remains untouched. The app lives in `mobile/` and `backend/`. This is a working prototype; the architecture migration, new financial features and remaining release work are tracked in the status document. Its current MYR default is legacy behavior to replace with explicit currency selection.
