import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _airportZones = <String, String>{
  'ICN': 'Asia/Seoul',
  'GMP': 'Asia/Seoul',
  'PUS': 'Asia/Seoul',
  'CJU': 'Asia/Seoul',
  'TAE': 'Asia/Seoul',
  'CJJ': 'Asia/Seoul',
  'KWJ': 'Asia/Seoul',
  'USN': 'Asia/Seoul',
  'RSU': 'Asia/Seoul',
  'NRT': 'Asia/Tokyo',
  'HND': 'Asia/Tokyo',
  'FUK': 'Asia/Tokyo',
  'KIX': 'Asia/Tokyo',
  'CTS': 'Asia/Tokyo',
  'NGO': 'Asia/Tokyo',
  'OKA': 'Asia/Tokyo',
  'TPE': 'Asia/Taipei',
  'BKK': 'Asia/Bangkok',
  'SIN': 'Asia/Singapore',
  'HKG': 'Asia/Hong_Kong',
  'PEK': 'Asia/Shanghai',
  'PVG': 'Asia/Shanghai',
  'CAN': 'Asia/Shanghai',
  'MNL': 'Asia/Manila',
  'HAN': 'Asia/Ho_Chi_Minh',
  'SGN': 'Asia/Ho_Chi_Minh',
  'DAD': 'Asia/Ho_Chi_Minh',
  'KUL': 'Asia/Kuala_Lumpur',
  'CGK': 'Asia/Jakarta',
  'DEL': 'Asia/Kolkata',
  'DXB': 'Asia/Dubai',
  'DOH': 'Asia/Qatar',
  'IST': 'Europe/Istanbul',
  'CDG': 'Europe/Paris',
  'LHR': 'Europe/London',
  'FRA': 'Europe/Berlin',
  'AMS': 'Europe/Amsterdam',
  'MAD': 'Europe/Madrid',
  'FCO': 'Europe/Rome',
  'JFK': 'America/New_York',
  'LAX': 'America/Los_Angeles',
  'SFO': 'America/Los_Angeles',
  'SEA': 'America/Los_Angeles',
  'ORD': 'America/Chicago',
  'YYZ': 'America/Toronto',
  'YVR': 'America/Vancouver',
  'MEX': 'America/Mexico_City',
  'GRU': 'America/Sao_Paulo',
  'SYD': 'Australia/Sydney',
  'MEL': 'Australia/Melbourne',
  'AKL': 'Pacific/Auckland',
  'JNB': 'Africa/Johannesburg',
};

class FlightSearchLimit implements Exception {}

class MobileFlightSearch {
  MobileFlightSearch(this._encodedKey, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String _encodedKey;
  final DateTime Function() _now;
  final _pools = <String, List<Map<String, dynamic>>>{};
  final _lastRefresh = <String, DateTime>{};
  final _refreshing = <String>{};
  static final _random = Random();
  DateTime? _blockedUntil;

  String get _key => utf8.decode(
    base64Decode(
      _encodedKey,
    ).indexed.map((entry) => entry.$2 ^ ((entry.$1 * 31 + 93) & 255)).toList(),
  );

  Stream<Map<String, dynamic>> search(
    String origin,
    List<String> destinations,
  ) async* {
    final now = _now();
    tzdata.initializeTimeZones();
    final zone = tz.getLocation(_airportZones[origin] ?? 'UTC');
    final local = tz.TZDateTime.from(now, zone);
    final today = DateTime.utc(local.year, local.month, local.day);
    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowDate = _date(tomorrow);
    final cached = _routes(
      _pools[origin] ?? [],
      destinations,
      now,
      tomorrowDate,
    );
    final cachedRoute = cached.isEmpty
        ? null
        : cached.values.elementAt(_random.nextInt(cached.length));
    String? selected = cachedRoute?['destination'] as String?;
    if (cachedRoute != null) {
      yield {...cachedRoute, 'cached': true};
      final last = _lastRefresh[origin];
      if ((last != null && now.difference(last) < const Duration(hours: 2)) ||
          (_blockedUntil?.isAfter(now) ?? false) ||
          _refreshing.contains(origin)) {
        return;
      }
    }
    if (_blockedUntil?.isAfter(now) ?? false) throw FlightSearchLimit();
    if (!_refreshing.add(origin)) return;
    _lastRefresh[origin] = now;
    final candidates = [
      ?selected,
      ...(destinations.where((code) => code != selected).toList()..shuffle()),
    ].take(4).toList();
    final offers = [
      for (final offer in _pools[origin] ?? const <Map<String, dynamic>>[])
        {...offer, 'cached': true},
    ];
    var succeeded = false;
    var limited = false;
    Map<String, dynamic>? shown = cachedRoute;
    try {
      final batches = Stream.fromFutures([
        for (final date in [today, tomorrow])
          _fetch(origin, candidates, date, zone)
              .then<List<Map<String, dynamic>>?>((value) => value)
              .catchError((Object error) {
                if (error is FlightSearchLimit) {
                  limited = true;
                  _blockedUntil = _now().add(const Duration(minutes: 5));
                }
                return null;
              }),
      ]);
      await for (final batch in batches) {
        if (batch == null) continue;
        succeeded = true;
        final refreshedRoutes = batch.map(_offerDay).toSet();
        offers.removeWhere(
          (offer) => refreshedRoutes.contains(_offerDay(offer)),
        );
        offers.addAll(batch);
        offers.sort((a, b) {
          final byTime = (a['departAtUtc'] as String).compareTo(
            b['departAtUtc'] as String,
          );
          return byTime != 0
              ? byTime
              : (a['amount'] as num).compareTo(b['amount'] as num);
        });
        final currentTime = _now();
        _pools[origin] = offers
            .where(
              (offer) =>
                  DateTime.parse(offer['departAtUtc']).isAfter(currentTime),
            )
            .toList();
        final routes = _routes(offers, destinations, currentTime, tomorrowDate);
        if (routes.isEmpty) continue;
        selected ??= routes.keys.elementAt(_random.nextInt(routes.length));
        final route = routes[selected];
        if (route == null ||
            (shown != null &&
                route['flight'] == shown['flight'] &&
                route['tomorrowFlight'] == shown['tomorrowFlight'])) {
          continue;
        }
        shown = route;
        yield {...route, 'cached': false};
      }
      if (shown == null && limited) throw FlightSearchLimit();
      if (shown == null && !succeeded) throw StateError('Flight lookup failed');
    } finally {
      _refreshing.remove(origin);
    }
  }

  (Object?, String) _offerDay(Map<String, dynamic> offer) =>
      (offer['destination'], (offer['depart'] as String).substring(0, 10));

  Map<String, Map<String, dynamic>> _routes(
    List<Map<String, dynamic>> offers,
    List<String> destinations,
    DateTime now,
    String tomorrowDate,
  ) {
    final routes = <String, Map<String, dynamic>>{};
    final deadline = now.add(const Duration(hours: 12));
    for (final offer in offers) {
      final departure = DateTime.parse(offer['departAtUtc']);
      if (!departure.isAfter(now)) continue;
      final destination = offer['destination'] as String;
      if (!destinations.contains(destination)) continue;
      final route = routes.putIfAbsent(
        destination,
        () => {'destination': destination},
      );
      final date = offer['depart'] as String;
      if (route['flight'] == null && !departure.isAfter(deadline)) {
        route['flight'] = offer;
      } else if (route['tomorrowFlight'] == null &&
          date.startsWith(tomorrowDate) &&
          int.parse(date.substring(11, 13)) >= 12 &&
          int.parse(date.substring(11, 13)) < 18 &&
          route['flight']?['departAtUtc'] != offer['departAtUtc']) {
        route['tomorrowFlight'] = offer;
      }
    }
    routes.removeWhere(
      (_, route) => route['flight'] == null && route['tomorrowFlight'] == null,
    );
    return routes;
  }

  static String _date(DateTime date) => date.toIso8601String().substring(0, 10);

  Future<List<Map<String, dynamic>>> _fetch(
    String origin,
    List<String> candidates,
    DateTime date,
    tz.Location zone,
  ) async {
    final response = await http
        .get(
          Uri.https('serpapi.com', '/search.json', {
            'engine': 'google_flights',
            'api_key': _key,
            'departure_id': origin,
            'arrival_id': candidates.join(','),
            'outbound_date': _date(date),
            'return_date': _date(date.add(const Duration(days: 3))),
            'type': '1',
            'currency': 'USD',
            'hl': 'en',
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) throw FlightSearchLimit();
    if (response.statusCode != 200) throw StateError('Flight lookup failed');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final metadata = body['search_metadata'] as Map?;
    if (metadata?['status'] != 'Success') {
      throw StateError('Flight lookup failed');
    }
    final processed = (metadata?['processed_at'] as String?)
        ?.replaceFirst(' ', 'T')
        .replaceFirst(' UTC', 'Z');
    final checked = (DateTime.tryParse(processed ?? '') ?? DateTime.now())
        .toUtc()
        .toIso8601String();
    final offers = <Map<String, dynamic>>[];
    for (final option in [
      ...?body['best_flights'] as List?,
      ...?body['other_flights'] as List?,
    ]) {
      final segments = option['flights'] as List?;
      final price = option['price'];
      if (segments == null || segments.isEmpty || price is! num || price <= 0) {
        continue;
      }
      final first = segments.first['departure_airport'] as Map?;
      final last = segments.last['arrival_airport'] as Map?;
      final depart = first?['time'] as String?;
      final arrive = last?['time'] as String?;
      final destination = last?['id'] as String?;
      if (first?['id'] != origin ||
          !candidates.contains(destination) ||
          depart == null ||
          arrive == null) {
        continue;
      }
      final wall = DateTime.tryParse('${depart.replaceFirst(' ', 'T')}Z');
      if (wall == null) continue;
      final departure = tz.TZDateTime(
        zone,
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
      );
      final connections = [
        for (final stop in option['layovers'] as List? ?? [])
          if (stop['id'] is String)
            {'code': stop['id'], 'minutes': stop['duration']},
      ];
      final duration = option['total_duration'] as int?;
      offers.add({
        'destination': destination,
        'airline': segments
            .map((s) => s['airline'])
            .whereType<String>()
            .toSet()
            .join(' + '),
        'depart': depart.replaceFirst(' ', 'T'),
        'arrive': arrive.replaceFirst(' ', 'T'),
        'departAtUtc': departure.toUtc().toIso8601String(),
        'duration': duration == null
            ? 'Unavailable'
            : '${duration ~/ 60}h ${duration % 60}m',
        'amount': price,
        'currency': 'USD',
        'checkedAt': checked,
        'via': [
          for (final segment in segments.take(segments.length - 1))
            if (segment['arrival_airport']?['id'] case final String code) code,
        ],
        'connections': connections,
        'kind': 'round-trip',
        'bookingUrl': metadata?['google_flights_url'],
        'outboundSegments': [
          for (final segment in segments)
            {
              'from': segment['departure_airport']?['id'],
              'to': segment['arrival_airport']?['id'],
              'depart': segment['departure_airport']?['time'],
              'arrive': segment['arrival_airport']?['time'],
              'number': segment['flight_number'],
            },
        ],
      });
    }
    return offers;
  }
}
