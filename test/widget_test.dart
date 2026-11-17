import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'dart:ui' as ui;
import 'package:elsewhere_travel/data.dart';
import 'package:elsewhere_travel/satellite_layer.dart';

void main() {
  test('nearest airport uses coordinates', () {
    final sorted = [...places]
      ..sort(
        (a, b) =>
            distance(37.46, 126.44, a).compareTo(distance(37.46, 126.44, b)),
      );
    expect(sorted.first.code, 'ICN');
  });

  testWidgets('bundled Earth texture paints on the globe', (tester) async {
    final image = await tester.runAsync(() async {
      final bytes = await rootBundle.load('assets/earth-blue-marble.jpg');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Globe(
              controller: GlobeController(autoRotate: false),
              autoRotate: false,
              layers: [SatelliteLayer(image!)],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    image.dispose();
  });
}
