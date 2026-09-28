# Pocketwise Flutter client

See the [project README](../README.md) for local API setup and run commands, [architecture](../docs/ARCHITECTURE.md) for the target View/Presenter/Model boundaries and prototype migration, and [testing](../docs/TESTING.md) for verification.

The app targets Android, iOS, and web. `API_URL` is a compile-time environment value; defaults are `http://10.0.2.2:8000` for Android and `http://localhost:8000` otherwise. Configure a reachable HTTPS API for release builds.

Bundled Roboto fonts are distributed under the license in `assets/fonts/Roboto_LICENSE.txt`.
