# Elsewhere

Flutter iOS, Android and Web spontaneous travel MVP. Run `flutter pub get && flutter run`, or `flutter run -d chrome` to inspect the web version.

The globe uses `flutter_globe` for the camera, flight arc and moving airplane. Its surface uses the NASA Blue Marble imagery bundled from the adjacent Terra Newsphere project. Landmark previews are bundled from Wikimedia Commons with author, license and source shown in the result card. Hover a thumbnail on desktop or tap it on mobile to enlarge the preview.

Flight selection defaults to departure within 12 hours and a three-day round trip. The existing live provider is Duffel: deploy `worker/` as a Cloudflare Worker, set `DUFFEL_TOKEN` with `npx wrangler secret put DUFFEL_TOKEN`, and launch the app with `--dart-define=FLIGHTS_API_URL=https://your-worker.example.workers.dev`. The token must be live-mode. The Worker caches each airport pair and search window at the Cloudflare edge for two minutes; a new route or an expired offer triggers a fresh lookup. Cache entries are local to a Cloudflare data center. Without a live provider key, the app shows a sample destination and no invented price.

Amadeus Self-Service ended in July 2026. An Amadeus Enterprise search contract, endpoint, authentication details and response schema are required before it can replace the current provider. Do not configure the retired Self-Service URL.

Before store release, replace starter icons and `com.example` app IDs, add a privacy policy URL, confirm provider agreements and entry requirements, and test on physical devices. The app has a curated airport list rather than a complete route network.
