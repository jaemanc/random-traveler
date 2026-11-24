# Random Traveler

A spontaneous travel app for iOS, Android, and web. Pick a departure airport, tap **Surprise Me**, and follow the flight across an interactive 3D globe.

![Random Traveler globe showing the Seoul to Taipei route, airport labels, and landmark thumbnails](docs/globe-preview.jpg)

## Landmark preview

The gallery appears on the globe after arrival. Hover over a thumbnail to enlarge it, or tap to pin the preview.

| Thumbnails | Expanded on hover |
| --- | --- |
| ![Landmark thumbnails along the globe](docs/landmark-thumbnails.jpg) | ![Enlarged Haeundae Beach photo above the thumbnails](docs/landmark-hover.jpg) |

## Run locally

```sh
flutter pub get
flutter run
```

For web, run `flutter run -d web-server` and open the printed URL in your browser. Sample mode needs no account or API key.

## Explore

- Allow location access to find the nearest airport in the catalog, or search 52 departure airports by partial city, country, or IATA code.
- Search for a destination to open a sample preview, or use **Surprise Me** to animate a random route. Hover over a landmark thumbnail for a larger preview. Move the pointer away to close it. On touchscreens, tap to pin it and tap again to close it.
- Drag the globe horizontally to rotate while keeping north up. Use the wheel, pinch, or zoom buttons. Country boundaries and airport labels gain detail as you zoom.
- At 2.8× zoom, the globe loads OpenStreetMap tiles for the current view and fades into an interactive map. Zoom out or use **Back to globe** to return. **Open Google Maps** opens the same location externally. For another licensed tile provider, pass `--dart-define=OSM_TILE_URL=https://your-host/{z}/{x}/{y}.png`.
- The layout adapts to the available width and keeps content clear of a reported foldable hinge.

## Live fares on iOS and Android

Add `SERPAPI_API_KEY` (or `sera_api_key`) to the ignored `.env`, then run on a connected mobile device or simulator:

```sh
./scripts/dev-mobile.sh -d <device-id>
```

The mobile app calls SerpApi directly and reuses the in-memory route list by departure airport while eligible flights remain. Cached fares appear immediately, with a background refresh on searches made at least two hours apart. It shows a search-limit message on HTTP 429. The launcher masks the key in the build configuration. A distributed app binary still contains a recoverable credential, so anyone who extracts it can consume the same quota.

### Test the mobile fare flow in Chrome

```sh
./scripts/dev-mobile.sh -d chrome
```

The launcher uses Flutter’s temporary Chrome profile with CORS checks disabled for this local debugging session. Use that window only for app testing. The debug app calls the same Dart fare service as mobile. A plain `flutter run -d chrome` does not inject the key or configure the browser for direct requests.

### Optional web Worker

To test with SerpApi, add `SERPAPI_API_KEY` to the ignored `.env` file (the existing `sera_api_key` name also works). Start the Worker and Flutter web app together:

```sh
./scripts/dev-web.sh
```

Open `http://127.0.0.1:8080`. Press `q` in the terminal to stop both processes. On Cloudflare, set `SERPAPI_API_KEY` as a Worker secret. When only a live Duffel token is configured, the Worker uses Duffel instead. To deploy with Duffel:

```sh
cd worker
npx wrangler secret put DUFFEL_TOKEN
npx wrangler deploy
cd ..
flutter run --dart-define=FLIGHTS_API_URL=https://your-worker.example.workers.dev
```

**Surprise Me** looks for the earliest departure within 12 hours and a separate option tomorrow from noon to 6 p.m. in the departure airport’s time zone. The quoted fares are for round trips returning three days after departure. The Worker caches route searches at the Cloudflare edge for up to two minutes. Live lookups support the 52-airport catalog. SerpApi groups up to four destinations per date and reuses the short-lived route pool for repeated recommendations. Connecting flights are eligible. If no fare is returned, the app shows a sample destination without a price.

## Checks and credits

```sh
flutter analyze
flutter test
```

Earth imagery is NASA Blue Marble. Country outlines use public domain Natural Earth data from TerraNewsphere. Landmark photos are from Wikimedia Commons, with source and license recorded in [the photo catalog](assets/attractions.json).

Before store release, replace the starter icons and app IDs, add a privacy policy URL, confirm provider terms, and test on physical devices.

Connecting airport coordinates are bundled from [OurAirports open data](https://github.com/davidmegginson/ourairports-data).
