This is a Flutter iOS/Android app. Keep all UI copy in English. Use the shared Dart codebase for app behavior and the existing Cloudflare Worker for live flight lookup.

Run `flutter pub get`, `flutter analyze`, and `flutter test` after relevant changes. Keep live provider tokens out of the app; pass only the Worker URL through `--dart-define=FLIGHTS_API_URL=...`. Sample mode must never display a fabricated flight fare.
