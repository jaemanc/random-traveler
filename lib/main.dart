import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'data.dart';
import 'home_ui.dart';
import 'globe_overlays.dart';
import 'satellite_layer.dart';

const gold = primaryBlue, panel = Color(0xfff8fbff), muted = secondaryText;
const api = String.fromEnvironment('FLIGHTS_API_URL');
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
    title: 'Elsewhere',
    theme: elsewhereTheme,
    home: const Home(),
  );
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
      kind = j['kind'] ?? 'one-way',
      via = (j['via'] as List? ?? []).cast<String>();
  final String airline, depart, arrive, duration, currency, checkedAt, kind;
  final double amount;
  final bool cached;
  final List<String> via;
}

class Trip {
  Trip(this.from, this.to, this.flight);
  final Place from, to;
  final Flight? flight;
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
  Place? origin;
  Trip? trip;
  String airportQuery = '';
  bool manual = false, busy = false, revealed = false;
  int revealVersion = 0, activePhoto = 0;
  Attraction? hoveredPhoto, pinnedPhoto;
  bool cameraInterrupted = false;
  AnimationController? cameraFlight;
  String notice = '';
  ui.Image? earth;
  Map<String, List<Attraction>> attractions = {};
  final capture = ScreenshotController();
  final fareSection = GlobalKey();
  final attractionSection = GlobalKey();
  List<List<Vector3D>> countryLines = const [];
  final globe = NorthUpGlobeController();
  @override
  void initState() {
    super.initState();
    _locate();
    _loadAssets();
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
        setState(() => manual = true);
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
      setState(() => origin = sorted.first);
      globe.rotation = northUpRotation(sorted.first.lat, sorted.first.lon);
    } catch (_) {
      setState(() => manual = true);
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
      trip = null;
      notice = '';
      revealed = false;
      activePhoto = 0;
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
              found = Trip(
                airport,
                to,
                Flight.fromJson(data['flight'], data['cached'] == true),
              );
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
      activePhoto = 0;
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
                              Expanded(flex: 11, child: globeSection),
                              const Spacer(flex: 2),
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
                        if (t != null && revealed) _result(t, tablet),
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
      const Text(
        'Elsewhere',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
      ),
      const Spacer(),
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
    if (!revealed ||
        (key == attractionSection &&
            (attractions[trip?.to.city] ?? []).isEmpty)) {
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

  Widget _globeView(Trip? t) => ClipRect(
    child: Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(event, (
                  _,
                ) {
                  _zoom(exp((-event.scrollDelta.dy / 260).clamp(-0.45, 0.45)));
                });
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
                      GlobeMarker(
                        coordinate: GlobeCoordinate(
                          latitude: t.from.lat,
                          longitude: t.from.lon,
                        ),
                        label: null,
                        pulse: true,
                      ),
                      GlobeMarker(
                        coordinate: GlobeCoordinate(
                          latitude: t.to.lat,
                          longitude: t.to.lon,
                        ),
                        label: null,
                        pulse: true,
                      ),
                    ],
              layers: [
                if (earth != null) SatelliteLayer(earth!),
                GlobeOverlays(countryLines, globe, {
                  if (t != null) ...[t.from.code, t.to.code],
                }),
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
        Positioned.fill(
          child: ListenableBuilder(
            listenable: globe,
            builder: (context, _) => globe.zoom >= 2.8
                ? DetailedMap(
                    center: globeCenter(globe.rotation),
                    onExit: (center) {
                      globe.rotation = northUpRotation(center.$1, center.$2);
                      globe.zoom = 2.45;
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (t != null && revealed && (attractions[t.to.city] ?? []).isNotEmpty)
          Positioned.fill(child: _photoPreview(t)),
      ],
    ),
  );

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

  Widget _result(Trip t, bool tablet) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Screenshot(
      controller: capture,
      child: Container(
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: Colors.white, width: 1.5),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: primaryBlue.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: tablet ? 3.2 : 1.6,
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
                        colors: [Colors.transparent, Color(0xb8192f60)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR NEXT ESCAPE IS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            letterSpacing: 3,
                          ),
                        ),
                        Text(
                          t.to.city,
                          style: TextStyle(
                            fontSize: tablet ? 40 : 34,
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          t.to.country,
                          style: const TextStyle(
                            color: Colors.white,
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
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        : t.flight!.cached
                        ? 'CACHED OFFER · PRICE MAY CHANGE'
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
                    Text(
                      f.via.isEmpty ? 'Nonstop' : 'Via ${f.via.join(', ')}',
                      style: const TextStyle(color: muted),
                    ),
                    const Divider(height: 35),
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
                  Text(
                    'LOWEST FARE FOUND',
                    key: fareSection,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    t.flight == null
                        ? 'Unavailable in sample mode'
                        : _money(t.flight!.amount, t.flight!.currency),
                    style: const TextStyle(color: navyText, fontSize: 24),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    t.flight == null
                        ? 'No flight price was returned. No sample fare is shown.'
                        : '${t.flight!.cached ? 'Duffel cache' : 'Duffel live search'} · Checked ${_date(t.flight!.checkedAt)} UTC · Price may change.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
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
        Flexible(
          child: Text(a, style: const TextStyle(color: muted)),
        ),
        const SizedBox(width: 8),
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
