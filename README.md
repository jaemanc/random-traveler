# Elsewhere

Flutter iOS, Android and Web spontaneous travel MVP. Run `flutter pub get && flutter run`, or `flutter run -d chrome` to inspect the web version.

The globe uses `flutter_globe` for the camera, flight arc and moving airplane. Its surface uses the NASA Blue Marble imagery bundled from the adjacent Terra Newsphere project. Drag to rotate, pinch or use the controls to zoom, and scroll over the globe on desktop to zoom. The bright Material 3 home layout places a destination photo card beside the globe on wide screens and below it on phones. Hover or tap its thumbnails to change the large preview. Destination search opens a local sample preview without a fare; Surprise Me retains live flight lookup when configured. Wikimedia author, license and source are shown in the result card.

Flight selection defaults to departure within 12 hours and a three-day round trip. The existing live provider is Duffel: deploy `worker/` as a Cloudflare Worker, set `DUFFEL_TOKEN` with `npx wrangler secret put DUFFEL_TOKEN`, and launch the app with `--dart-define=FLIGHTS_API_URL=https://your-worker.example.workers.dev`. The token must be live-mode. The Worker caches each airport pair and search window at the Cloudflare edge for two minutes; a new route or an expired offer triggers a fresh lookup. Cache entries are local to a Cloudflare data center. Without a live provider key, the app shows a sample destination and no invented price.

Amadeus Self-Service ended in July 2026. An Amadeus Enterprise search contract, endpoint, authentication details and response schema are required before it can replace the current provider. Do not configure the retired Self-Service URL.

Before store release, replace starter icons and `com.example` app IDs, add a privacy policy URL, confirm provider agreements and entry requirements, and test on physical devices. The app has a curated airport list rather than a complete route network.

At 2.8× zoom, the globe loads visible OpenStreetMap tiles and fades into an interactive north-up map. No Google key is required. Use the map controls to return to the globe or open the same location in Google Maps. For a different licensed OSM tile host, pass `--dart-define=OSM_TILE_URL=https://your-host/{z}/{x}/{y}.png`. Country outlines are simplified from TerraNewsphere's Natural Earth 5.1.2 country dataset (public domain).
