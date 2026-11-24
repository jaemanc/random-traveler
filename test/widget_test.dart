import 'package:elsewhere_travel/globe_overlays.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elsewhere_travel/data.dart';
import 'package:elsewhere_travel/main.dart';
import 'package:flutter_globe/flutter_globe.dart';

void main() {
  test('round trip route follows its outbound connections in order', () {
    final from = departureAirports.firstWhere((p) => p.code == 'GMP');
    final to = departureAirports.firstWhere((p) => p.code == 'FRA');
    final flight = Flight.fromJson({
      'amount': 200,
      'via': ['KIX', 'HEL'],
    }, false);
    final trip = Trip(from, to, null, flight);
    final route = trip.routeAirports({
      'KIX': [34.43, 135.24],
      'HEL': [60.32, 24.96],
    });
    expect(route.map((p) => p.code), ['GMP', 'KIX', 'HEL', 'FRA']);
  });

  test('nearest airport uses coordinates', () {
    final sorted = [...places]
      ..sort(
        (a, b) =>
            distance(37.46, 126.44, a).compareTo(distance(37.46, 126.44, b)),
      );
    expect(sorted.first.code, 'ICN');
  });

  test('repeated diagonal drags cannot roll or flip the globe', () {
    final controller = NorthUpGlobeController();
    addTearDown(controller.dispose);
    controller.rotation = northUpRotation(37.46, 126.44);
    for (var i = 0; i < 50; i++) {
      controller.rotateBy(0.2, 0.3);
    }
    final (lat, lon) = globeCenter(controller.rotation);
    expect(lat, closeTo(37.46, 0.000001));
    final north = controller.rotation.rotateVector(
      Vector3D.fromDegrees(lat + 1, lon),
    );
    expect(north.x, closeTo(0, 0.000001));
    expect(north.y, lessThan(0));
  });

  test('destination camera keeps north above the center', () {
    final rotation = northUpRotation(37.46, 126.44);
    final (lat, lon) = globeCenter(rotation);
    expect(lat, closeTo(37.46, 0.000001));
    expect(lon, closeTo(126.44, 0.000001));
    final center = rotation.rotateVector(Vector3D.fromDegrees(37.46, 126.44));
    final north = rotation.rotateVector(Vector3D.fromDegrees(38.46, 126.44));
    expect(center.x, closeTo(0, 0.000001));
    expect(center.y, closeTo(0, 0.000001));
    expect(center.z, closeTo(1, 0.000001));
    expect(north.x, closeTo(0, 0.000001));
    expect(north.y, lessThan(0));
  });
}
