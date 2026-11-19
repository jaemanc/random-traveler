import 'package:flutter_test/flutter_test.dart';
import 'package:elsewhere_travel/data.dart';
import 'package:elsewhere_travel/main.dart';
import 'package:flutter_globe/flutter_globe.dart';

void main() {
  test('nearest airport uses coordinates', () {
    final sorted = [...places]
      ..sort(
        (a, b) =>
            distance(37.46, 126.44, a).compareTo(distance(37.46, 126.44, b)),
      );
    expect(sorted.first.code, 'ICN');
  });

  test('destination camera keeps north above the center', () {
    final rotation = northUpRotation(37.46, 126.44);
    final center = rotation.rotateVector(Vector3D.fromDegrees(37.46, 126.44));
    final north = rotation.rotateVector(Vector3D.fromDegrees(38.46, 126.44));
    expect(center.x, closeTo(0, 0.000001));
    expect(center.y, closeTo(0, 0.000001));
    expect(center.z, closeTo(1, 0.000001));
    expect(north.x, closeTo(0, 0.000001));
    expect(north.y, lessThan(0));
  });
}
