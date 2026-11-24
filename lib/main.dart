import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'home_ui.dart';
import 'flight_search.dart';
import 'globe_overlays.dart';
import 'satellite_layer.dart';

const gold = primaryBlue, panel = Color(0xfff8fbff), muted = secondaryText;
const mobileFlightKey = String.fromEnvironment('SERPAPI_MOBILE_CONFIG');
final localBrowser =
    kIsWeb && const {'localhost', '127.0.0.1', '::1'}.contains(Uri.base.host);
final mobileFlights =
    mobileFlightKey.isNotEmpty && (!kIsWeb || (kDebugMode && localBrowser))
    ? MobileFlightSearch(mobileFlightKey)
    : null;
const configuredFlightApi = String.fromEnvironment('FLIGHTS_API_URL');
final api = configuredFlightApi.isNotEmpty
    ? configuredFlightApi
    : localBrowser
    ? 'http://127.0.0.1:8787'
    : '';
void main() => runApp(const Elsewhere());

Quaternion3D northUpRotation(double lat, double lon) =>
    (Quaternion3D.fromAxisAngle(Vector3D.unitX, -lat * pi / 180) *
            Quaternion3D.fromAxisAngle(Vector3D.unitY, -lon * pi / 180))
        .normalized;

class NorthUpGlobeController extends GlobeController {
  NorthUpGlobeController()
    : super(autoRotate: false, initialRotation: northUpRotation(0, 0));

  @override
  void rotateBy(double deltaYaw, double deltaPitch) {
    // Drag around the geographic axis without tilting toward either pole.
    if (deltaYaw == 0) return;
    final (lat, lon) = globeCenter(rotation);
    rotation = northUpRotation(lat, lon - deltaYaw * 180 / pi);
  }
}

class Elsewhere extends StatelessWidget {
  const Elsewhere({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Random Traveler',
    theme: elsewhereTheme,
    home: const Home(),
  );
}

class FlightSegment {
  FlightSegment.fromJson(Map<String, dynamic> json)
    : from = json['from'] ?? '',
      to = json['to'] ?? '',
      depart = json['depart'] ?? '',
      arrive = json['arrive'] ?? '',
      number = json['number'] ?? '';

  final String from, to, depart, arrive, number;
}

class Flight {
  Flight.fromJson(Map<String, dynamic> j, this.cached)
    : airline = j['airline'] ?? '',
      depart = j['depart'] ?? '',
      arrive = j['arrive'] ?? '',
      duration = j['duration'] ?? '',
      amount = (j['amount'] as num).toDouble(),
      currency = j['currency'] ?? 'USD',
      checkedAt = j['checkedAt'] ?? '',
      kind = j['kind'] ?? '',
      bookingUrl = Uri.tryParse(j['bookingUrl'] as String? ?? ''),
      outboundSegments = _segments(j['outboundSegments']),
      returnSegments = _segments(j['returnSegments']),
      via = (j['via'] as List? ?? []).cast<String>(),
      departAtUtc = DateTime.tryParse(j['departAtUtc'] as String? ?? ''),
      connections = [
        for (final Map<String, dynamic> stop
            in (j['connections'] as List? ?? []))
          if (stop['code'] is String && stop['minutes'] is num)
            (stop['code'] as String, (stop['minutes'] as num).round()),
      ];
  static List<FlightSegment> _segments(Object? value) => [
    if (value is List)
      for (final segment in value.whereType<Map<String, dynamic>>())
        if (segment['from'] is String && segment['to'] is String)
          FlightSegment.fromJson(segment),
  ];

  final Uri? bookingUrl;
  final List<FlightSegment> outboundSegments, returnSegments;
  bool get includesReturnFare => kind == 'round-trip';
  final String airline, depart, arrive, duration, currency, checkedAt, kind;
  final double amount;
  final bool cached;
  final List<String> via;
  final DateTime? departAtUtc;
  final List<(String, int)> connections;
}

class Trip {
  Trip(this.from, this.to, this.flight, [this.tomorrowFlight]);
  final Place from, to;
  final Flight? flight, tomorrowFlight;

  List<Place> routeAirports(Map<String, dynamic> coordinates) => [
    from,
    for (final code in (flight ?? tomorrowFlight)?.via ?? const <String>[])
      if (coordinates[code] case [final num lat, final num lon])
        Place(code, '', '', '', lat.toDouble(), lon.toDouble(), 0),
    to,
  ];
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

class _HomeState extends State<Home> with TickerProviderStateMixin {
  Place? origin = departureAirports[Random().nextInt(departureAirports.length)];
  bool originChosenManually = false;
  Trip? trip;
  String airportQuery = '';
  bool manual = false, busy = false, revealed = false;
  int revealVersion = 0;
  Attraction? hoveredPhoto, pinnedPhoto;
  bool cameraInterrupted = false;
  SearchFlightBurst? searchBurst;
  AnimationController? cameraFlight;
  String notice = '';
  ui.Image? earth;
  Map<String, List<Attraction>> attractions = {};
  Map<String, dynamic> airportCoordinates = {};
  final capture = ScreenshotController();
  final fareSection = GlobalKey();
  final attractionSection = GlobalKey();
  List<List<Vector3D>> countryLines = const [];
  final globe = NorthUpGlobeController();
  @override
  void initState() {
    super.initState();
    globe.rotation = northUpRotation(origin!.lat, origin!.lon);
    _locate();
    _loadAssets();
    rootBundle.loadString('assets/airport-coordinates.json').then((data) {
      if (mounted) {
        setState(
          () => airportCoordinates = jsonDecode(data) as Map<String, dynamic>,
        );
      }
    });
    loadCountryLines().then((lines) {
      if (mounted) setState(() => countryLines = lines);
    });
  }

  @override
  void dispose() {
    cameraFlight?.dispose();
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
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final sorted = [...departureAirports]
        ..sort(
          (a, b) => distance(
            pos.latitude,
            pos.longitude,
            a,
          ).compareTo(distance(pos.latitude, pos.longitude, b)),
        );
      if (!mounted || originChosenManually || busy || trip != null) return;
      setState(() => origin = sorted.first);
      globe.rotation = northUpRotation(sorted.first.lat, sorted.first.lon);
    } catch (_) {
      // Keep the initially selected airport when location is unavailable.
    }
  }

  void _fly(Place from, Place to, int version) {
    cameraFlight?.dispose();
    cameraFlight = null;
    cameraInterrupted = false;
    globe.rotation = northUpRotation(from.lat, from.lon);
    globe.zoom = 1;
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || revealVersion != version || cameraInterrupted) return;
      final (lat, lon) = globeCenter(globe.rotation);
      final longitudeDelta = (to.lon - lon + 540) % 360 - 180;
      final animation = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      );
      cameraFlight = animation;
      animation.addListener(() {
        final progress = Curves.easeInOutCubic.transform(animation.value);
        globe.rotation = northUpRotation(
          lat + (to.lat - lat) * progress,
          lon + longitudeDelta * progress,
        );
        globe.zoom = 1 + 0.01 * progress;
      });
      animation.forward();
    });
  }

  void _zoom(double factor) {
    cameraInterrupted = true;
    cameraFlight?.stop();
    globe.zoom = (globe.zoom * factor).clamp(0.5, 3.5).toDouble();
  }

  List<Place> get destinations => places
      .where((p) => p.code != origin?.code && p.city != origin?.city)
      .toList();
  Future<void> _surprise() async {
    final from = origin;
    if (from == null) return;
    setState(() {
      busy = true;
      searchBurst = SearchFlightBurst();
      trip = null;
      notice = '';
      revealed = false;
      hoveredPhoto = pinnedPhoto = null;
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
    bool failed = false, limitReached = false;
    if (mobileFlights != null || api.isNotEmpty) {
      // Keep the candidate group stable so repeated taps reuse the same pool.
      final candidates = departureAirports
          .where(
            (airport) => airport.code != from.code && airport.city != from.city,
          )
          .toList();
      try {
        final Map<String, dynamic> data;
        if (mobileFlights case final search?) {
          data = await search.search(
            from.code,
            candidates.map((p) => p.code).toList(),
          );
        } else {
          final uri = Uri.parse(api).replace(
            queryParameters: {
              'origin': from.code,
              'destination': candidates
                  .map((airport) => airport.code)
                  .join(','),
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
          data = jsonDecode(response.body) as Map<String, dynamic>;
        }
        if (data['flight'] != null || data['tomorrowFlight'] != null) {
          final to = candidates.firstWhere(
            (airport) => airport.code == data['destination'],
          );
          found = Trip(
            from,
            to,
            _parseFlight(data['flight'], data['cached'] == true),
            _parseFlight(data['tomorrowFlight'], data['cached'] == true),
          );
        }
      } on FlightSearchLimit {
        limitReached = true;
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    found ??= Trip(from, targets.first, null);
    setState(() {
      trip = found;
      busy = false;
      searchBurst = null;
      if (found?.flight == null && found?.tomorrowFlight == null) {
        notice = limitReached
            ? 'Flight search limit reached. Try again later.'
            : api.isEmpty && mobileFlights == null
            ? 'Live fares are not configured.'
            : failed
            ? 'The flight service could not complete the request.'
            : 'No live fares found in the next 12 hours.';
      }
    });
    _fly(found.from, found.to, version);
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && revealVersion == version) setState(() => revealed = true);
    });
  }

  void _selectDestination(Place to) {
    if (busy) return;
    final from = origin;
    if (from == null) {
      setState(() => notice = 'Choose a departure airport first.');
      return;
    }
    final version = ++revealVersion;
    setState(() {
      trip = Trip(from, to, null);
      revealed = false;
      hoveredPhoto = pinnedPhoto = null;
      notice = 'Destination preview · no live fare';
    });
    _fly(from, to, version);
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && revealVersion == version) setState(() => revealed = true);
    });
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
              name: 'random-traveler-trip.png',
            ),
          ],
          fileNameOverrides: const ['random-traveler-trip.png'],
          text: 'My next escape: ${trip!.to.city}, ${trip!.to.country}',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => notice = 'Could not share this trip.');
    }
  }

  String _money(num n, [String currency = 'USD']) =>
      '${currency == 'USD' ? '\$' : '$currency '}${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)}';
  String _date(String x) =>
      x.substring(0, min(16, x.length)).replaceFirst('T', '  ');
  Widget _button(String text, VoidCallback? tap) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: tap,
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: Colors.white,
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
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffeaf5ff), Color(0xffdceeff), Color(0xfff8fbff)],
        ),
      ),
      child: DisplayFeatureSubScreen(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final wide = width >= 1100;
              final tablet = width >= 600;
              final t = trip;
              final shortSide = min(width, constraints.maxHeight);
              final gutter = (shortSide * 0.04).clamp(12.0, 32.0);
              final gap = gutter * 0.85;
              final globeSection = LayoutBuilder(
                builder: (context, pane) => Padding(
                  padding: EdgeInsets.only(top: gap * 0.6),
                  child: SizedBox(
                    height: min(
                      pane.maxWidth,
                      constraints.maxHeight * (wide ? 0.68 : 0.74),
                    ),
                    child: _globeView(t),
                  ),
                ),
              );
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(gutter, gap, gutter, gutter * 1.5),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1450),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(tablet),
                        SizedBox(height: gap),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 3, child: _heroCopy(true)),
                              Expanded(flex: 10, child: globeSection),
                              const Spacer(flex: 3),
                            ],
                          )
                        else ...[
                          _heroCopy(false),
                          SizedBox(height: gap),
                          globeSection,
                        ],
                        SizedBox(height: gap),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: _controls()),
                              SizedBox(width: gap),
                              Expanded(flex: 4, child: _surpriseCard()),
                            ],
                          )
                        else ...[
                          _controls(),
                          SizedBox(height: gap),
                          _surpriseCard(),
                        ],
                        SizedBox(height: gap),
                        _shortcuts(),
                        if (t != null) _result(t),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _header(bool tablet) => Row(
    children: [
      const Icon(Icons.auto_awesome, color: primaryBlue, size: 30),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Random Traveler',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
      ),
      if (tablet) ...[
        const Chip(
          label: Text('Explore'),
          avatar: Icon(Icons.home_outlined, size: 18),
          backgroundColor: Color(0xffcfe3ff),
          side: BorderSide.none,
        ),
        const SizedBox(width: 10),
        const Text(
          'Trips',
          style: TextStyle(color: muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 24),
        const Text(
          'Saved',
          style: TextStyle(color: muted, fontWeight: FontWeight.w600),
        ),
      ],
    ],
  );

  Widget _heroCopy(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'A LITTLE SPONTANEITY',
        style: TextStyle(color: muted, fontSize: 11, letterSpacing: 2.5),
      ),
      const SizedBox(height: 18),
      Text.rich(
        const TextSpan(
          children: [
            TextSpan(text: 'Go somewhere\n'),
            TextSpan(
              text: 'unexpected.',
              style: TextStyle(color: primaryBlue, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        style: TextStyle(
          fontSize: wide && MediaQuery.sizeOf(context).width < 1280
              ? 34
              : wide
              ? 43
              : 38,
          height: 1.12,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Discover a new place. Let the world surprise you.',
        style: TextStyle(color: muted, fontSize: 16, height: 1.5),
      ),
    ],
  );

  Widget _controls() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 570;
            final airport = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DEPARTING FROM',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 9),
                InkWell(
                  onTap: () => setState(() {
                    manual = !manual;
                    airportQuery = '';
                  }),
                  child: Row(
                    children: [
                      const Icon(Icons.flight_takeoff, color: primaryBlue),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          origin == null
                              ? 'Choose an airport'
                              : '${origin!.city} · ${origin!.code}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: primaryBlue),
                    ],
                  ),
                ),
              ],
            );
            final destination = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WHERE TO?',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                Autocomplete<Place>(
                  displayStringForOption: (p) => '${p.city}, ${p.country}',
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return const Iterable<Place>.empty();
                    return places
                        .where(
                          (p) =>
                              p.code != origin?.code &&
                              ('${p.city} ${p.country} ${p.code}')
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .take(8);
                  },
                  onSelected: _selectDestination,
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmitted) =>
                          TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search a city or country',
                              border: InputBorder.none,
                              isDense: true,
                              prefixIcon: const Icon(
                                Icons.place_outlined,
                                color: primaryBlue,
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Preview destination',
                                icon: const Icon(
                                  Icons.arrow_forward,
                                  color: primaryBlue,
                                ),
                                onPressed: () {
                                  final query = controller.text
                                      .trim()
                                      .toLowerCase();
                                  final matches = places.where(
                                    (p) =>
                                        p.code != origin?.code &&
                                        ('${p.city} ${p.country} ${p.code}')
                                            .toLowerCase()
                                            .contains(query),
                                  );
                                  if (query.isNotEmpty && matches.isNotEmpty) {
                                    _selectDestination(matches.first);
                                  } else {
                                    setState(
                                      () => notice = 'No matching destination.',
                                    );
                                  }
                                },
                              ),
                            ),
                            onSubmitted: (_) => onSubmitted(),
                          ),
                ),
              ],
            );
            return wide
                ? Row(
                    children: [
                      Expanded(child: airport),
                      const SizedBox(width: 24),
                      Expanded(child: destination),
                    ],
                  )
                : Column(
                    children: [
                      airport,
                      const SizedBox(height: 18),
                      destination,
                    ],
                  );
          },
        ),
        if (manual) _airportPicker(),
        if (notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              notice,
              style: const TextStyle(color: primaryBlue, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _airportPicker() {
    final query = airportQuery.trim().toLowerCase().split(RegExp(r'\s+'));
    final matches = departureAirports.where((p) {
      final label =
          '${p.city} ${p.code} ${p.country} ${p.countryCode} ${GlobeOverlays.names[p.code] ?? ''}'
              .toLowerCase();
      return query.every(label.contains);
    }).toList();
    return Column(
      children: [
        TextField(
          onChanged: (value) => setState(() => airportQuery = value),
          decoration: const InputDecoration(
            labelText: 'Search departure airports',
            hintText: 'City, country, or IATA code',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No matching airports'),
          )
        else
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * 0.25).clamp(
              144.0,
              320.0,
            ),
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (_, index) {
                final p = matches[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    title: Text('${p.city}  ${p.code}'),
                    subtitle: Text(p.country),
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        origin = p;
                        originChosenManually = true;
                        manual = false;
                        airportQuery = '';
                      });
                      cameraInterrupted = true;
                      cameraFlight?.stop();
                      globe.rotation = northUpRotation(p.lat, p.lon);
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _surpriseCard() => GlassCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✦  Surprise Me',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Not sure where to go? Let chance choose.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 14),
              _button(
                busy ? 'SEARCHING...' : 'SURPRISE ME',
                origin == null || busy ? null : _surprise,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.travel_explore, size: 54, color: primaryBlue),
      ],
    ),
  );

  Widget _shortcuts() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _Shortcut(Icons.flight_outlined, 'Flights', _jumpTo(fareSection)),
      const _Shortcut(Icons.hotel_outlined, 'Stays', null),
      _Shortcut(
        Icons.local_activity_outlined,
        'Attractions',
        _jumpTo(attractionSection),
      ),
      const _Shortcut(Icons.directions_car_outlined, 'Transport', null),
    ],
  );

  VoidCallback? _jumpTo(GlobalKey key) {
    if (trip == null ||
        (key == attractionSection &&
            (!revealed || (attractions[trip?.to.city] ?? []).isEmpty))) {
      return null;
    }
    return () {
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 350),
        );
      }
    };
  }

  Widget _globeView(Trip? t) {
    final routeAirports = t?.routeAirports(airportCoordinates) ?? [?origin];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {
                      _zoom(
                        exp((-event.scrollDelta.dy / 260).clamp(-0.45, 0.45)),
                      );
                    },
                  );
                }
              },
              child: Globe(
                key: ValueKey(t?.to.code),
                controller: globe,
                theme: GlobeSkins.midnight.copyWith(
                  atmosphere: const GlobeAtmosphereStyle(
                    color: Color(0xffa6c9d3),
                    altitude: 0.08,
                    glowIntensity: 0.2,
                    innerShadowIntensity: 0.08,
                  ),
                  surface: GlobeSkins.midnight.surface.copyWith(
                    surfaceColor: const Color(0xff061624),
                    pointOpacity: 0,
                  ),
                ),
                radiusMultiplier: 0.89,
                enableZoom: true,
                onInteractionStart: () {
                  cameraInterrupted = true;
                  cameraFlight?.stop();
                },
                quality: GlobeQuality.auto,
                autoRotate: false,
                markers: t == null
                    ? const []
                    : [
                        for (final airport in routeAirports)
                          GlobeMarker.latLng(
                            latitude: airport.lat,
                            longitude: airport.lon,
                            label:
                                GlobeOverlays.airports.containsKey(airport.code)
                                ? null
                                : airport.code,
                            pulse: false,
                          ),
                      ],
                layers: [
                  if (earth != null) SatelliteLayer(earth!),
                  GlobeOverlays(countryLines, globe, {
                    if (t != null)
                      ...routeAirports.map((airport) => airport.code),
                  }),
                  if (t == null && !reduceMotion) const AmbientFlights(),
                  if (busy && !reduceMotion) ?searchBurst,
                  if (t != null)
                    GlobeRouteLayer(
                      routes: [
                        GlobeRoute(
                          waypoints: [
                            for (final airport in routeAirports)
                              GlobeCoordinate(
                                latitude: airport.lat,
                                longitude: airport.lon,
                              ),
                          ],
                          color: gold,
                          vehicleColor: const Color(0xffeaf5ff),
                          vehicleSize: 10,
                          showVehicle: !revealed && !reduceMotion,
                          duration: const Duration(milliseconds: 4400),
                          repeat: false,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Zoom in',
                  onPressed: () => _zoom(1.4),
                  icon: const Icon(Icons.add),
                ),
                IconButton.filledTonal(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(1 / 1.4),
                  icon: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: muted),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                busy
                    ? 'SEARCHING FOR FLIGHTS…'
                    : t == null
                    ? 'YOUR NEXT JOURNEY'
                    : [
                        t.from.code,
                        ...(t.flight ?? t.tomorrowFlight)?.via ??
                            const <String>[],
                        t.to.code,
                      ].join('  →  '),
                style: const TextStyle(
                  color: gold,
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ListenableBuilder(
              listenable: globe,
              builder: (context, _) => globe.zoom >= 2.8
                  ? DetailedMap(
                      center: globeCenter(globe.rotation),
                      airports: routeAirports,
                      onExit: (center) {
                        globe.rotation = northUpRotation(center.$1, center.$2);
                        globe.zoom = 2.45;
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (t != null &&
              revealed &&
              (attractions[t.to.city] ?? []).isNotEmpty)
            Positioned.fill(child: _photoPreview(t)),
        ],
      ),
    );
  }

  Widget _photoPreview(Trip t) => LayoutBuilder(
    key: attractionSection,
    builder: (context, bounds) {
      final photos = attractions[t.to.city]!;
      final size = min(
        bounds.maxHeight * 0.15,
        bounds.maxWidth * 0.92 / photos.length,
      );
      final bottom = bounds.maxHeight * 0.16;
      final previewWidth = min(
        bounds.maxWidth * 0.82,
        bounds.maxHeight * 0.44 * 16 / 9,
      );
      final preview = hoveredPhoto ?? pinnedPhoto;
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (preview != null)
            Positioned(
              bottom: bottom + size * 1.13,
              width: previewWidth,
              height: previewWidth * 9 / 16,
              child: IgnorePointer(
                child: Material(
                  key: const ValueKey('landmark-preview'),
                  color: Colors.white,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(preview.asset, fit: BoxFit.cover),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          color: const Color(0xcc192f60),
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            preview.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: bottom,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, photo) in photos.indexed)
                  SizedBox(
                    key: ValueKey('landmark-thumbnail-$index'),
                    width: size,
                    height: size,
                    child: Padding(
                      padding: EdgeInsets.all(size * 0.07),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => hoveredPhoto = photo),
                        onExit: (_) => setState(() => hoveredPhoto = null),
                        child: GestureDetector(
                          supportedDevices: const {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.invertedStylus,
                          },
                          onTap: () => setState(() {
                            pinnedPhoto = pinnedPhoto == photo ? null : photo;
                          }),
                          child: Semantics(
                            button: true,
                            label: photo.title,
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Image.asset(
                                photo.asset,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Flight? _parseFlight(Object? value, bool cached) =>
      value is Map<String, dynamic> ? Flight.fromJson(value, cached) : null;

  String _minutes(int minutes) =>
      minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h ${minutes % 60}m';

  Uri _bookingLink(Trip trip, Flight flight) {
    final url = flight.bookingUrl;
    if (url != null &&
        url.scheme == 'https' &&
        url.host == 'www.google.com' &&
        url.path.startsWith('/travel/flights') &&
        url.queryParameters.containsKey('tfs')) {
      return url;
    }
    return Uri.https('www.google.com', '/search', {
      'q':
          'Google Flights ${trip.from.code} to ${trip.to.code} ${flight.depart.split(RegExp(r"[ T]")).first}',
    });
  }

  String _flightTime(String value) {
    final match = RegExp(r'[T ](\d{2}:\d{2})').firstMatch(value);
    return match?.group(1) ?? '—';
  }

  Widget _flightDetails(String title, Trip trip, Flight flight) {
    final now = DateTime.now();
    final remaining = flight.departAtUtc?.difference(now).inMinutes;
    final checked = DateTime.tryParse(flight.checkedAt)?.toLocal();
    final departureDate = flight.depart.split(RegExp(r'[ T]')).first;
    final scope = flight.includesReturnFare
        ? 'Outbound + return total'
        : flight.kind == 'one-way'
        ? 'One-way fare'
        : 'Fare scope unavailable';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (departureDate.isNotEmpty)
                  Text(
                    departureDate,
                    style: const TextStyle(color: primaryBlue),
                  ),
              ],
            ),
            Text(
              _money(flight.amount, flight.currency),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Text(
          '${flight.currency} · 1 adult · $scope',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 10),
        Text(
          flight.airline,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (remaining != null)
          Text(
            remaining > 0
                ? 'Departs in ${_minutes(remaining)}'
                : flight.departAtUtc!.isAfter(now)
                ? 'Departs in under 1m'
                : 'Departure time passed',
          ),
        const SizedBox(height: 12),
        Text(
          'OUTBOUND · ${flight.duration} · ${flight.via.isEmpty ? 'Nonstop' : '${flight.via.length} ${flight.via.length == 1 ? 'stop' : 'stops'}'}',
          style: const TextStyle(
            color: primaryBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Text(
          'Times are local to each airport.',
          style: TextStyle(color: muted),
        ),
        if (flight.outboundSegments.isNotEmpty)
          _itinerary(flight.outboundSegments, connections: flight.connections)
        else
          Text('${_date(flight.depart)} → ${_date(flight.arrive)}'),
        if (flight.includesReturnFare) ...[
          const SizedBox(height: 14),
          const Text(
            'RETURN',
            style: TextStyle(color: primaryBlue, fontWeight: FontWeight.w700),
          ),
          if (flight.returnSegments.isNotEmpty)
            _itinerary(flight.returnSegments)
          else
            const Text(
              'Select the return flight on the booking site.',
              style: TextStyle(color: muted),
            ),
        ],
        const SizedBox(height: 12),
        if (checked != null)
          Text(
            'Fare checked ${_date(checked.toIso8601String())} ${checked.timeZoneName}${flight.cached ? ' · Cached' : ''}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            if (!await launchUrl(_bookingLink(trip, flight)) && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open flight booking.')),
              );
            }
          },
          icon: const Icon(Icons.open_in_new, size: 17),
          label: const Text('Find & book flights'),
        ),
      ],
    );
  }

  Widget _itinerary(
    List<FlightSegment> segments, {
    List<(String, int)> connections = const [],
  }) => Column(
    children: [
      for (final (i, segment) in segments.indexed) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              [
                'Layover · ${segments[i - 1].to}',
                for (final (code, minutes) in connections)
                  if (code == segments[i - 1].to) _minutes(minutes),
                if (segments[i - 1].to != segment.from)
                  'Change airport to ${segment.from}',
              ].join(' · '),
              style: const TextStyle(color: muted),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xffeaf5ff),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(child: _segmentEndpoint(segment.from, segment.depart)),
              Expanded(
                child: Column(
                  children: [
                    const Icon(
                      Icons.flight_takeoff,
                      color: primaryBlue,
                      size: 17,
                    ),
                    Text(
                      segment.number.isEmpty ? 'No flight no.' : segment.number,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _segmentEndpoint(
                  segment.to,
                  segment.arrive,
                  arrival: true,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _segmentEndpoint(String code, String time, {bool arrival = false}) =>
      Column(
        crossAxisAlignment: arrival
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            _flightTime(time),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (time.length >= 10)
            Text(
              time.substring(0, 10),
              textAlign: arrival ? TextAlign.end : TextAlign.start,
              style: const TextStyle(fontSize: 10, color: muted),
            ),
        ],
      );

  Widget _result(Trip t) {
    final hasFlights = t.flight != null || t.tomorrowFlight != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 690),
        child: FractionallySizedBox(
          widthFactor: 0.96,
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Screenshot(
              controller: capture,
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasFlights ? 'FLIGHT OPTIONS' : 'TRIP PREVIEW',
                      style: const TextStyle(
                        color: primaryBlue,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _ticketAirport(t.from)),
                        const Icon(Icons.flight_takeoff, color: primaryBlue),
                        Expanded(child: _ticketAirport(t.to, arrival: true)),
                      ],
                    ),
                    const Divider(height: 28),
                    KeyedSubtree(
                      key: fareSection,
                      child: hasFlights
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (t.flight case final flight?)
                                  _flightDetails(
                                    'Earliest departure',
                                    t,
                                    flight,
                                  ),
                                if (t.flight != null &&
                                    t.tomorrowFlight != null)
                                  const Divider(height: 24),
                                if (t.tomorrowFlight case final flight?)
                                  _flightDetails(
                                    'Tomorrow afternoon',
                                    t,
                                    flight,
                                  ),
                              ],
                            )
                          : const Text(
                              'Sample trip. No live fare or itinerary was returned.',
                              style: TextStyle(color: muted),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _surprise,
                          child: const Text('Surprise Me Again'),
                        ),
                        TextButton(
                          onPressed: _share,
                          child: const Text('Share My Trip'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ticketAirport(Place airport, {bool arrival = false}) => Column(
    crossAxisAlignment: arrival
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        airport.code,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
      ),
      Text(airport.city, textAlign: arrival ? TextAlign.end : TextAlign.start),
      if (airport.country.toLowerCase() != airport.city.toLowerCase())
        Text(
          airport.country,
          textAlign: arrival ? TextAlign.end : TextAlign.start,
          style: const TextStyle(color: muted),
        ),
    ],
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.icon, this.label, this.onPressed);
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(4),
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
