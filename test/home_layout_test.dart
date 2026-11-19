import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:elsewhere_travel/main.dart';

void main() {
  testWidgets('desktop reveals photos beside a zoomable globe', (tester) async {
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
    await tester.ensureVisible(find.text('Seoul  ICN'));
    await tester.tap(find.text('Seoul  ICN'));
    await tester.pump();
    await tester.ensureVisible(find.text('SURPRISE ME'));
    await tester.tap(find.text('SURPRISE ME'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('DESTINATION PREVIEW'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    final globe = tester.widget<Globe>(find.byType(Globe));
    expect(globe.enableZoom, isTrue);
    final beforeZoom = globe.controller!.zoom;
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
    tester.view.physicalSize = const Size(900, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GridView), findsOneWidget);
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
