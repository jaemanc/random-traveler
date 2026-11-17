import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'data.dart';
import 'satellite_layer.dart';

const gold = Color(0xffeac58d),
    bg = Color(0xff08121c),
    panel = Color(0xff0d1b29),
    muted = Color(0xff9caebc);
const api = String.fromEnvironment('FLIGHTS_API_URL');
void main() => runApp(const Elsewhere());

class Elsewhere extends StatelessWidget {
  const Elsewhere({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Elsewhere',
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: bg),
    home: const Home(),
  );
}

class Flight {
  Flight.fromJson(Map<String, dynamic> j)
    : airline = j['airline'] ?? '',
      depart = j['depart'] ?? '',
      arrive = j['arrive'] ?? '',
      duration = j['duration'] ?? '',
      amount = (j['amount'] as num).toDouble(),
      currency = j['currency'] ?? 'USD',
      checkedAt = j['checkedAt'] ?? '',
      kind = j['kind'] ?? 'one-way';
  final String airline, depart, arrive, duration, currency, checkedAt, kind;
  final double amount;
}

class Trip {
  Trip(this.from, this.to, this.flight);
  final Place from, to;
  final Flight? flight;
}

class SkyscannerFare {
  SkyscannerFare.fromJson(Map<String, dynamic> j)
    : amount = (j['amount'] as num).toDouble(),
      currency = j['currency'] as String,
      date = j['date'] as String;
  final double amount;
  final String currency, date;
}

class Attraction {
  Attraction.fromJson(Map<String, dynamic> j)
    : title = j['title'] as String,
      asset = j['asset'] as String,
      author = j['author'] as String,
      license = j['license'] as String,
      source = j['source'] as String;
  final String title, asset, author, license, source;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  Place? origin;
  Trip? trip;
  bool manual = false, busy = false, revealed = false, fareLoading = false;
  int revealVersion = 0, activePhoto = 0;
  String notice = '';
  ui.Image? earth;
  SkyscannerFare? skyscannerFare;
  Map<String, List<Attraction>> attractions = {};
  final capture = ScreenshotController();
  late final GlobeController globe = GlobeController(autoRotate: false);
  @override
  void initState() {
    super.initState();
    _locate();
    _loadAssets();
  }

  @override
  void dispose() {
    earth?.dispose();
    globe.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final data = await rootBundle.load('assets/earth-blue-marble.jpg');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    final decoded =
        jsonDecode(await rootBundle.loadString('assets/attractions.json'))
            as Map<String, dynamic>;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      earth = image;
      attractions = decoded.map(
        (city, photos) => MapEntry(
          city,
          (photos as List)
              .map((p) => Attraction.fromJson(p as Map<String, dynamic>))
              .toList(),
        ),
      );
    });
  }

  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => manual = true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final sorted = [...places]
        ..sort(
          (a, b) => distance(
            pos.latitude,
            pos.longitude,
            a,
          ).compareTo(distance(pos.latitude, pos.longitude, b)),
        );
      setState(() => origin = sorted.first);
      globe.lookAt(
        GlobeCoordinate(
          latitude: sorted.first.lat,
          longitude: sorted.first.lon,
        ),
      );
    } catch (_) {
      setState(() => manual = true);
    }
  }

  void _fly(Place from, Place to, int version) {
    globe.lookAt(GlobeCoordinate(latitude: from.lat, longitude: from.lon));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && revealVersion == version) {
        globe.animateTo(
          coordinate: GlobeCoordinate(latitude: to.lat, longitude: to.lon),
          vsync: this,
          duration: const Duration(milliseconds: 2600),
          zoom: 1.25,
        );
      }
    });
  }

  List<Place> get destinations => places
      .where((p) => p.code != origin?.code && p.city != origin?.city)
      .toList();
  Future<void> _surprise() async {
    final from = origin;
    if (from == null) return;
    setState(() {
      busy = true;
      trip = null;
      notice = '';
      revealed = false;
      skyscannerFare = null;
      activePhoto = 0;
    });
    final version = ++revealVersion;
    final targets = destinations..shuffle();
    if (targets.isEmpty) {
      setState(() {
        busy = false;
        notice = 'No destinations match this filter.';
      });
      return;
    }
    Trip? found;
    bool failed = false;
    if (api.isNotEmpty) {
      final nearby = [
        from,
        ...(places.where((p) => p.code != from.code).toList()..sort(
              (a, b) => distance(
                from.lat,
                from.lon,
                a,
              ).compareTo(distance(from.lat, from.lon, b)),
            ))
            .take(2),
      ];
      for (final airport in nearby) {
        for (final to in targets.take(6)) {
          if (airport.code == to.code || airport.city == to.city) continue;
          try {
            final uri = Uri.parse(api).replace(
              queryParameters: {
                'origin': airport.code,
                'destination': to.code,
                'hours': '12',
                'kind': 'round-trip',
              },
            );
            final response = await http
                .get(uri)
                .timeout(const Duration(seconds: 35));
            if (response.statusCode != 200) {
              throw Exception('Flight lookup unavailable');
            }
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            if (data['flight'] != null) {
              found = Trip(airport, to, Flight.fromJson(data['flight']));
              break;
            }
          } catch (_) {
            failed = true;
            break;
          }
        }
        if (found != null || failed) break;
      }
    }
    if (!mounted) return;
    found ??= Trip(from, targets.first, null);
    setState(() {
      trip = found;
      busy = false;
      if (failed) {
        notice =
            'Live flight search is unavailable. Showing a sample destination.';
      }
    });
    _fly(found.from, found.to, version);
    _loadSkyscanner(found);
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && revealVersion == version) setState(() => revealed = true);
    });
  }

  Future<void> _loadSkyscanner(Trip t) async {
    if (api.isEmpty) return;
    setState(() => fareLoading = true);
    try {
      final uri = Uri.parse(api).replace(
        queryParameters: {
          'provider': 'skyscanner',
          'origin': t.from.code,
          'destination': t.to.code,
          'hours': '12',
          'kind': 'round-trip',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted && trip == t && data['fare'] != null) {
        setState(() => skyscannerFare = SkyscannerFare.fromJson(data['fare']));
      }
    } catch (_) {
      /* Price remains unavailable. */
    }
    if (mounted && trip == t) setState(() => fareLoading = false);
  }

  Future<void> _share() async {
    try {
      final bytes = await capture.capture(pixelRatio: 2);
      if (bytes == null) throw Exception();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'elsewhere-trip.png',
            ),
          ],
          fileNameOverrides: const ['elsewhere-trip.png'],
          text: 'My next escape: ${trip!.to.city}, ${trip!.to.country}',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => notice = 'Could not share this trip.');
    }
  }

  String _money(num n, [String currency = 'USD']) =>
      '${currency == 'USD' ? '\$' : '$currency '}${n.round()}';
  String _date(String x) =>
      x.replaceFirst('T', '  ').substring(0, min(16, x.length));
  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 23, bottom: 10),
    child: Text(
      t,
      style: const TextStyle(
        color: muted,
        fontSize: 10,
        letterSpacing: 2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  Widget _button(String text, VoidCallback? tap) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: tap,
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: bg,
        padding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final t = trip;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '✦  ELSEWHERE',
                          style: TextStyle(
                            color: gold,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        if (width > 500)
                          const Text(
                            'THE WORLD IS WAITING',
                            style: TextStyle(
                              color: muted,
                              fontSize: 9,
                              letterSpacing: 2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 38, 24, 0),
                    child: Text(
                      'A LITTLE SPONTANEITY',
                      style: TextStyle(
                        color: gold,
                        fontSize: 10,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Go somewhere\n'),
                          TextSpan(
                            text: 'unexpected.',
                            style: TextStyle(
                              color: gold,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: Text(
                      'One tap. A new horizon. Your next story starts here.',
                      style: TextStyle(color: muted, fontSize: 14),
                    ),
                  ),
                  SizedBox(
                    height: 330,
                    child: Stack(
                      children: [
                        Globe(
                          key: ValueKey(t?.to.code),
                          controller: globe,
                          theme: GlobeSkins.midnight.copyWith(
                            atmosphere: const GlobeAtmosphereStyle(
                              color: Color(0xff5aa7bb),
                            ),
                            surface: GlobeSkins.midnight.surface.copyWith(
                              surfaceColor: const Color(0xff061624),
                              pointOpacity: 0.01,
                            ),
                          ),
                          quality: GlobeQuality.auto,
                          autoRotate: t == null,
                          markers: t == null
                              ? const []
                              : [
                                  GlobeMarker(
                                    coordinate: GlobeCoordinate(
                                      latitude: t.from.lat,
                                      longitude: t.from.lon,
                                    ),
                                    label: t.from.code,
                                    pulse: true,
                                  ),
                                  GlobeMarker(
                                    coordinate: GlobeCoordinate(
                                      latitude: t.to.lat,
                                      longitude: t.to.lon,
                                    ),
                                    label: t.to.code,
                                    pulse: true,
                                  ),
                                ],
                          layers: [
                            if (earth != null) SatelliteLayer(earth!),
                            if (t != null)
                              GlobeRouteLayer(
                                routes: [
                                  GlobeRoute(
                                    waypoints: [
                                      GlobeCoordinate(
                                        latitude: t.from.lat,
                                        longitude: t.from.lon,
                                      ),
                                      GlobeCoordinate(
                                        latitude: t.to.lat,
                                        longitude: t.to.lon,
                                      ),
                                    ],
                                    color: gold,
                                    vehicleColor: gold,
                                    duration: const Duration(
                                      milliseconds: 4400,
                                    ),
                                    repeat: false,
                                  ),
                                ],
                              ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 17,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: panel,
                              border: Border.all(color: muted),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              t == null
                                  ? 'YOUR NEXT JOURNEY'
                                  : '${t.from.code}  →  ${t.to.code}',
                              style: const TextStyle(
                                color: gold,
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('DEPARTING FROM'),
                        InkWell(
                          onTap: () => setState(() => manual = !manual),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(17),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xff354553),
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              origin == null
                                  ? 'Choose an airport'
                                  : '${origin!.city} · ${origin!.code}     ⌄',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        if (manual)
                          SizedBox(
                            height: 205,
                            child: ListView(
                              children: [
                                for (final p in places)
                                  ListTile(
                                    dense: true,
                                    title: Text('${p.city}  ${p.code}'),
                                    onTap: () {
                                      setState(() {
                                        origin = p;
                                        manual = false;
                                      });
                                      globe.lookAt(
                                        GlobeCoordinate(
                                          latitude: p.lat,
                                          longitude: p.lon,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 28),
                        _button(
                          busy ? 'SEARCHING...' : '✦   SURPRISE ME',
                          origin == null || busy ? null : _surprise,
                        ),
                        if (notice.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              notice,
                              style: const TextStyle(color: gold, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (t != null && revealed) _result(t),
                  const Padding(
                    padding: EdgeInsets.all(35),
                    child: Center(
                      child: Text(
                        'GO LIGHT. GO FAR. GO NOW.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _result(Trip t) => Padding(
    padding: const EdgeInsets.all(24),
    child: Screenshot(
      controller: capture,
      child: Container(
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: const Color(0xff30404b)),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 360,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((attractions[t.to.city] ?? []).isNotEmpty)
                    Image.asset(
                      attractions[t.to.city]![activePhoto %
                              attractions[t.to.city]!.length]
                          .asset,
                      fit: BoxFit.cover,
                    )
                  else
                    const ColoredBox(color: Color(0xff305b68)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, panel],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR NEXT ESCAPE IS',
                          style: TextStyle(
                            color: gold,
                            fontSize: 10,
                            letterSpacing: 3,
                          ),
                        ),
                        Text(
                          t.to.city,
                          style: const TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        Text(
                          t.to.country,
                          style: const TextStyle(
                            color: gold,
                            fontSize: 15,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if ((attractions[t.to.city] ?? []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EXPLORE THE LANDMARKS',
                      style: TextStyle(
                        color: gold,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (
                            var i = 0;
                            i < attractions[t.to.city]!.length;
                            i++
                          )
                            MouseRegion(
                              onEnter: (_) => setState(() => activePhoto = i),
                              child: GestureDetector(
                                onTap: () => setState(() => activePhoto = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: activePhoto == i ? 220 : 132,
                                  margin: const EdgeInsets.only(right: 8),
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset(
                                        attractions[t.to.city]![i].asset,
                                        fit: BoxFit.cover,
                                      ),
                                      const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Color(0xcc000000),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 10,
                                        right: 10,
                                        bottom: 10,
                                        child: Text(
                                          attractions[t.to.city]![i].title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Photo: ${attractions[t.to.city]![activePhoto % attractions[t.to.city]!.length].author} · ${attractions[t.to.city]![activePhoto % attractions[t.to.city]!.length].license}',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          attractions[t.to.city]![activePhoto %
                                  attractions[t.to.city]!.length]
                              .source,
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text(
                        'PHOTO & LICENSE ↗',
                        style: TextStyle(color: gold, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.flight == null
                        ? 'SAMPLE DESTINATION · NO LIVE FARE'
                        : 'LIVE OFFER · PRICE MAY CHANGE',
                    style: const TextStyle(
                      color: gold,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${t.from.code}  →  ${t.to.code}',
                    style: const TextStyle(fontSize: 25),
                  ),
                  if (t.flight case final f?) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${f.airline} · ${f.kind}',
                      style: const TextStyle(color: muted),
                    ),
                    Text(
                      '${_date(f.depart)}  →  ${_date(f.arrive)}',
                      style: const TextStyle(color: muted),
                    ),
                    Text(
                      'Travel time: ${f.duration}',
                      style: const TextStyle(color: muted),
                    ),
                    const Divider(height: 35),
                    _cost('Flight fare', _money(f.amount, f.currency)),
                    _cost(
                      'Local budget · 3 days, estimate',
                      '≈ ${_money(t.to.daily * 3)}',
                    ),
                    const Text(
                      'Local budget is a rough USD estimate; lodging, visas and transfers may vary.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    if (f.currency == 'USD')
                      _cost(
                        'Estimated total',
                        _money(f.amount + t.to.daily * 3),
                      ),
                    Text(
                      'Fare checked ${_date(f.checkedAt)}. Confirm availability and entry requirements before booking.',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Explore this destination. Flight schedules and prices are unavailable in sample mode.',
                        style: TextStyle(color: muted, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'SKYSCANNER INDICATIVE LOW FARE',
                    style: TextStyle(
                      color: gold,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    fareLoading
                        ? 'Checking Skyscanner…'
                        : skyscannerFare == null
                        ? 'Unavailable — partner access required'
                        : _money(
                            skyscannerFare!.amount,
                            skyscannerFare!.currency,
                          ),
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    skyscannerFare == null
                        ? 'No Skyscanner price was returned. No sample fare is shown.'
                        : 'Lowest recently seen for ${skyscannerFare!.date} · 1 adult economy. Cached price, not a live ticket offer.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  if (skyscannerFare != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: InkWell(
                        onTap: () => launchUrl(
                          Uri.parse('https://www.skyscanner.net'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Image.asset(
                          'assets/skyscanner-powered-by.png',
                          width: 150,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _surprise,
                        child: const Text(
                          'SURPRISE ME AGAIN',
                          style: TextStyle(color: gold, fontSize: 10),
                        ),
                      ),
                      TextButton(
                        onPressed: _share,
                        child: const Text(
                          'SHARE MY TRIP  ↗',
                          style: TextStyle(color: gold, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Earth: NASA Blue Marble · Photos: Wikimedia Commons',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _cost(String a, String b) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: const TextStyle(color: muted)),
        Text(
          b,
          style: const TextStyle(
            color: gold,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
