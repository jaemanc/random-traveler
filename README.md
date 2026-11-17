# Elsewhere

Flutter iOS/Android spontaneous travel MVP. The globe uses [`flutter_globe`](https://pub.dev/packages/flutter_globe): Flutter Canvas rendering, an animated route and a moving airplane. No WebView is used.

Run `flutter pub get && flutter run`. To check the web version, run `flutter run -d chrome` or `flutter build web`. For live fares, deploy `worker/` as a Cloudflare Worker, set `DUFFEL_TOKEN` with `npx wrangler secret put DUFFEL_TOKEN`, and run Flutter with `--dart-define=FLIGHTS_API_URL=https://your-worker.example.workers.dev`. Use a Duffel **live-mode** token. Never put it in the app. Without the URL, the app runs in sample mode and shows no invented fare.

The app uses on-device location to sort a curated airport list. Live search tries nearby airports and up to six random destinations. The Worker caches results for two minutes. Duffel offers can expire; Find Flights opens a separate search that may show a different fare. Daily local budgets are static USD estimates, not quotes. Destination images use Unsplash URLs; failed images fall back to a solid color.

Before store submission: replace starter icons, add a privacy policy URL, validate provider coverage and the external flight link, and profile the globe on physical iOS and Android devices. The package author notes limited physical-device validation.
