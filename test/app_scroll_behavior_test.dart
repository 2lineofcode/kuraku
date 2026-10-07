import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/core/app_scroll_behavior.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('macOS $axis scroll stays within both edges', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        scrollBehavior: appScrollBehavior,
        home: Scaffold(body: SingleChildScrollView(
          controller: controller,
          scrollDirection: axis,
          child: const SizedBox(width: 2000, height: 2000),
        )),
      ));
      final scrollable = find.byType(Scrollable);
      final position = controller.position;
      expect(position.physics, isA<ClampingScrollPhysics>());
      expect(find.byType(Scrollbar), axis == Axis.vertical ? findsOneWidget : findsNothing);
      expect(find.byType(GlowingOverscrollIndicator), findsNothing);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
      final delta = axis == Axis.vertical ? const Offset(0, 200) : const Offset(200, 0);
      final gesture = await tester.startGesture(tester.getCenter(scrollable));
      await gesture.moveBy(delta);
      await tester.pump();
      expect(position.pixels, position.minScrollExtent);
      await gesture.up();
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final endGesture = await tester.startGesture(tester.getCenter(scrollable));
      await endGesture.moveBy(-delta);
      await tester.pump();
      expect(position.pixels, position.maxScrollExtent);
      await endGesture.up();
      await tester.pumpAndSettle();
      await tester.drag(scrollable, delta);
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(position.maxScrollExtent));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
