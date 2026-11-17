import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'data.dart';

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

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  Place? origin;
  Trip? trip;
  bool manual = false, busy = false, imageFailed = false;
  int hours = 12;
  String region = 'Anywhere', kind = 'round-trip', notice = '';
  final capture = ScreenshotController();
  late final GlobeController globe = GlobeController(autoRotate: false);
  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    globe.dispose();
    super.dispose();
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

  void _fly(Place from, Place to) {
    globe.lookAt(GlobeCoordinate(latitude: from.lat, longitude: from.lon));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
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
      .where(
        (p) =>
            p.code != origin?.code &&
            p.city != origin?.city &&
            (region == 'Anywhere' ||
                (region == 'Domestic') ==
                    (p.countryCode == origin?.countryCode)),
      )
      .toList();
  Future<void> _surprise() async {
    final from = origin;
    if (from == null) return;
    setState(() {
      busy = true;
      trip = null;
      notice = '';
      imageFailed = false;
    });
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
                'hours': '$hours',
                'kind': kind,
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
    _fly(found.from, found.to);
  }

  Future<void> _openFlights() async {
    final t = trip;
    if (t == null) return;
    final date =
        t.flight?.depart.substring(0, 10) ??
        DateTime.now().toIso8601String().substring(0, 10);
    final url = Uri.parse(
      'https://www.google.com/travel/flights?hl=en#flt=${t.from.code}.${t.to.code}.$date;c:USD;e:1;sd:1;t:f',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => notice = 'Could not open flight search.');
    }
  }

  Future<void> _share() async {
    try {
      final bytes = await capture.capture(pixelRatio: 2);
      if (bytes == null) throw Exception();
      final file = File(
        '${(await getTemporaryDirectory()).path}/elsewhere-trip.png',
      );
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
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
  Widget _chip(String text, bool selected, VoidCallback tap) => InkWell(
    onTap: tap,
    borderRadius: BorderRadius.circular(30),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? gold : Colors.transparent,
        border: Border.all(color: selected ? gold : const Color(0xff344450)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: selected ? bg : muted,
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
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
                          skin: GlobeSkins.midnight,
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
                          layers: t == null
                              ? const []
                              : [
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
                        _label('LEAVING WITHIN'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final h in [12, 24, 48])
                              _chip(
                                '$h hours',
                                hours == h,
                                () => setState(() => hours = h),
                              ),
                          ],
                        ),
                        _label('WHERE TO?'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final r in ['Anywhere', 'Domestic', 'Abroad'])
                              _chip(
                                r,
                                region == r,
                                () => setState(() => region = r),
                              ),
                          ],
                        ),
                        _label('TICKET'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chip(
                              'Round trip',
                              kind == 'round-trip',
                              () => setState(() => kind = 'round-trip'),
                            ),
                            _chip(
                              'One way',
                              kind == 'one-way',
                              () => setState(() => kind = 'one-way'),
                            ),
                          ],
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
                  if (t != null) _result(t),
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
                  if (!imageFailed)
                    Image.network(
                      t.to.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => imageFailed = true);
                        });
                        return const ColoredBox(color: Color(0xff305b68));
                      },
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
                  _button('FIND FLIGHTS  ↗', _openFlights),
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
                    'Destination imagery: Unsplash',
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
