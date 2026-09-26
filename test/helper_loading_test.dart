import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/utils/helper_loading.dart';

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
    await tester.pump(duration);
  }

  testWidgets('shows a blocking dialog with the given message and closes on dismiss', (tester) async {
    await pump(tester);

    HelperLoading.show(message: 'Scanning library...');
    await settle(tester);

    expect(Get.isDialogOpen, isTrue);
    expect(find.text('Scanning library...'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Get.isDialogOpen, isFalse);
    expect(find.text('Scanning library...'), findsNothing);
  });

  testWidgets('without a message it counts the elapsed time and stops when dismissed', (tester) async {
    await pump(tester);

    HelperLoading.show();
    await settle(tester);
    expect(Get.isDialogOpen, isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.textContaining('seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Get.isDialogOpen, isFalse);
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
    expect(Get.isDialogOpen, isTrue, reason: 'a custom callback owns the dialog lifetime');

    HelperLoading.dismiss();
    await settle(tester, const Duration(seconds: 1));
    expect(Get.isDialogOpen, isFalse);
  });

  testWidgets('the default cancel action closes the dialog', (tester) async {
    await pump(tester);

    HelperLoading.show();
    await settle(tester);
    await tester.pump(const Duration(seconds: 16));
    await settle(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester, const Duration(seconds: 1));
    expect(Get.isDialogOpen, isFalse);
  });

  testWidgets('dismiss is a no-op when nothing is showing', (tester) async {
    await pump(tester);

    HelperLoading.dismiss();
    HelperLoading.dismiss();
    await settle(tester);

    expect(Get.isDialogOpen, anyOf(isFalse, isNull));
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
