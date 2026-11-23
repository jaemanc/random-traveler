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
  MobileFlightSearch(this._encodedKey);

  final String _encodedKey;
  final _pools =
      <String, ({DateTime fetched, List<Map<String, dynamic>> offers})>{};
  DateTime? _blockedUntil;

  String get _key => utf8.decode(
    base64Decode(
      _encodedKey,
    ).indexed.map((entry) => entry.$2 ^ ((entry.$1 * 31 + 93) & 255)).toList(),
  );

  Future<Map<String, dynamic>> search(
    String origin,
    List<String> destinations,
  ) async {
    final now = DateTime.now();
    if (_blockedUntil?.isAfter(now) ?? false) throw FlightSearchLimit();
    tzdata.initializeTimeZones();
    final zone = tz.getLocation(_airportZones[origin] ?? 'UTC');
    final local = tz.TZDateTime.from(now, zone);
    final today = DateTime.utc(local.year, local.month, local.day);
    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowDate = _date(tomorrow);
    var pool = _pools[origin];
    final cached =
        pool != null &&
        now.difference(pool.fetched) < const Duration(minutes: 2);
    if (!cached) {
      final candidates = (destinations.toList()..shuffle()).take(4).toList();
      try {
        final batches = await Future.wait([
          for (final date in [today, tomorrow])
            _fetch(origin, candidates, date, zone),
        ]);
        final offers = batches.expand((batch) => batch).toList()
          ..sort((a, b) {
            final byTime = (a['departAtUtc'] as String).compareTo(
              b['departAtUtc'] as String,
            );
            return byTime != 0
                ? byTime
                : (a['amount'] as num).compareTo(b['amount'] as num);
          });
        pool = (fetched: DateTime.now(), offers: offers);
        _pools[origin] = pool;
      } on FlightSearchLimit {
        _blockedUntil = now.add(const Duration(minutes: 5));
        rethrow;
      }
    }
    final routes = <String, Map<String, dynamic>>{};
    final deadline = now.add(const Duration(hours: 12));
    for (final offer in pool.offers) {
      final departure = DateTime.parse(offer['departAtUtc']);
      if (!departure.isAfter(now)) continue;
      final destination = offer['destination'] as String;
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
    final choices = routes.values
        .where(
          (route) => route['flight'] != null || route['tomorrowFlight'] != null,
        )
        .toList();
    return {
      if (choices.isNotEmpty) ...choices[Random().nextInt(choices.length)],
      'cached': cached,
    };
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
        .timeout(const Duration(seconds: 30));
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
        'via': [for (final stop in connections) stop['code']],
        'connections': connections,
        'kind': 'round-trip',
      });
    }
    return offers;
  }
}
