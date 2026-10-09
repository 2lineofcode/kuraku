import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/widgets/widget_surfaces.dart';
import 'package:javit/app/utils/helper_loading.dart';
import 'package:overlayment/overlayment.dart';

void main() {
  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();
  }

  /// The loader animates forever, so frames are pumped manually instead of
  /// waiting for the tree to settle.
  Future<void> settle(WidgetTester tester, [Duration duration = const Duration(milliseconds: 400)]) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(duration);
  }

  testWidgets('shows a loading overlay with the given message and closes on dismiss', (tester) async {
    await pump(tester);

    HelperLoading.show(message: 'Scanning library...');
    await settle(tester);

    expect(Overlayment.count, 1);
    expect(find.text('Scanning library...'), findsOneWidget);
    expect(find.byType(AppPanel), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Overlayment.count, 0);
    expect(find.text('Scanning library...'), findsNothing);
  });

  testWidgets('without a message it counts the elapsed time and stops when dismissed', (tester) async {
    await pump(tester);

    HelperLoading.show();
    await settle(tester);
    expect(Overlayment.count, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.textContaining('seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers a cancel action after fifteen seconds and runs the callback', (tester) async {
    await pump(tester);
    var cancelled = 0;

    HelperLoading.show(message: 'Importing...', cancelCallback: () => cancelled++);
    await settle(tester);
    expect(find.text('Cancel'), findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await settle(tester);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(cancelled, 1);
    expect(Overlayment.count, 1, reason: 'a custom callback owns the overlay lifetime');

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Overlayment.count, 0);
  });

  testWidgets('the default cancel action closes the overlay', (tester) async {
    await pump(tester);

    HelperLoading.show();
    await settle(tester);
    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester, const Duration(seconds: 1));
    expect(Overlayment.count, 0);
  });

  testWidgets('dismiss is a no-op when nothing is showing', (tester) async {
    await pump(tester);

    HelperLoading.dismiss();
    HelperLoading.dismiss();
    await settle(tester);

    expect(Overlayment.count, 0);
    expect(find.byType(AppPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading appears above an existing panel and dismiss preserves that panel', (tester) async {
    await pump(tester);
    final panel = OverPanel(child: const Text('Existing panel'));
    unawaited(Overlayment.show(panel, context: Get.context));
    await tester.pumpAndSettle();

    HelperLoading.show(message: 'Loading on top...', isDismissible: false);
    await settle(tester);
    expect(Overlayment.count, 2);
    expect(find.text('Loading on top...').hitTestable(), findsOneWidget);
    expect(find.text('Existing panel').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(Overlayment.count, 2);

    HelperLoading.dismiss();
    await settle(tester);
    expect(Overlayment.count, 1);
    expect(find.text('Existing panel').hitTestable(), findsOneWidget);

    unawaited(Overlayment.dismiss(panel));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
  });

  testWidgets('outside dismissal cleans timers and immediate dismissal is safe', (tester) async {
    await pump(tester);
    HelperLoading.show();
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(Overlayment.count, 0);

    HelperLoading.show();
    HelperLoading.dismiss();
    await settle(tester);
    await settle(tester);
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
  });

}
