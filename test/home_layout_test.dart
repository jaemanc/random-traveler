import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:elsewhere_travel/globe_overlays.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:elsewhere_travel/main.dart';

void main() {
  testWidgets('desktop reveals photos over a zoomable globe', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const Elsewhere());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    if (find.text('Seoul  ICN').evaluate().isEmpty) {
      await tester.ensureVisible(find.text('Choose an airport'));
      await tester.tap(find.text('Choose an airport'));
      await tester.pump();
    }
    final airportSearch = find.widgetWithText(
      TextField,
      'Search departure airports',
    );
    await tester.ensureVisible(airportSearch);
    await tester.enterText(airportSearch, 'seat');
    await tester.pump();
    expect(find.text('Seattle  SEA'), findsOneWidget);
    await tester.enterText(airportSearch, 'seo ic');
    await tester.pump();
    expect(find.text('Seoul  GMP'), findsNothing);
    await tester.ensureVisible(find.text('Seoul  ICN'));
    await tester.tap(find.text('Seoul  ICN'));
    await tester.pump();
    await tester.ensureVisible(find.byType(Globe));
    await tester.pump();
    final controller = tester.widget<Globe>(find.byType(Globe)).controller!;
    final (beforeLat, beforeLon) = globeCenter(controller.rotation);
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(Globe)),
    );
    await drag.moveBy(const Offset(45, 0));
    await drag.moveBy(const Offset(45, 120));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 300));
    final (afterLat, afterLon) = globeCenter(controller.rotation);
    expect(afterLat, closeTo(beforeLat, 0.000001));
    expect(afterLon, isNot(closeTo(beforeLon, 0.000001)));
    await tester.ensureVisible(find.text('SURPRISE ME'));
    await tester.tap(find.text('SURPRISE ME'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('landmark-thumbnail-0')), findsWidgets);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byKey(const ValueKey('landmark-thumbnail-0')), findsWidgets);
    final globe = tester.widget<Globe>(find.byType(Globe));
    expect(globe.enableZoom, isTrue);
    final beforeZoom = globe.controller!.zoom;
    await tester.ensureVisible(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(globe.controller!.zoom, greaterThan(beforeZoom));
    final afterButton = globe.controller!.zoom;
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(Globe))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();
    expect(globe.controller!.zoom, greaterThan(afterButton));
    final thumbnail = find.byKey(const ValueKey('landmark-thumbnail-0')).first;
    await tester.ensureVisible(thumbnail);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(thumbnail)));
    await tester.pump();
    final preview = find.byKey(const ValueKey('landmark-preview'));
    expect(
      tester.getSize(preview).height,
      greaterThan(tester.getSize(thumbnail).height * 2),
    );
    await tester.tap(thumbnail);
    await tester.sendEventToBinding(pointer.hover(Offset.zero));
    await tester.pump();
    expect(preview, findsOneWidget);
    tester.view.physicalSize = const Size(900, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    final unfoldedPreview = tester.getSize(preview);
    tester.view.displayFeatures = const [
      DisplayFeature(
        bounds: Rect.fromLTWH(435, 0, 30, 844),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.unknown,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    await tester.pump();
    expect(tester.getRect(find.byType(Globe)).right, lessThanOrEqualTo(435));
    expect(tester.getSize(preview).width, lessThan(unfoldedPreview.width));
    expect(tester.takeException(), isNull);
    tester.view.resetDisplayFeatures();
    tester.view.physicalSize = const Size(320, 680);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('landmark-thumbnail-0')), findsWidgets);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'Tokyo');
    await tester.pump();
    await tester.tap(find.text('Tokyo, Japan').last);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('SAMPLE DESTINATION · NO LIVE FARE'), findsOneWidget);
    expect(find.text('Tokyo'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
