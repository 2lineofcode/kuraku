import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/utils/helper_toast.dart';
import 'package:toastification/toastification.dart';

void main() {
  setUp(HomePanelAppLog.clear);
  tearDown(() {
    HomePanelAppLog.clear();
    Get.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('every toast flavour shows its message and mirrors it into the app log', (tester) async {
    await pump(tester);
    const short = Duration(seconds: 1);

    for (final toast in [
      ('error', () => HelperToast.error('Disk is gone', duration: short), 'Disk is gone', 'ERROR'),
      ('success', () => HelperToast.success('Library scanned', duration: short), 'Library scanned', 'SUCCESS'),
      ('info', () => HelperToast.info('12 new videos', duration: short), '12 new videos', 'INFO'),
      ('warn', () => HelperToast.warn('Drive is almost full', duration: short), 'Drive is almost full', 'WARN'),
    ]) {
      await toast.$2();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(toast.$3), findsOneWidget, reason: 'toast ${toast.$1}');
      expect(find.byType(HugeIcon), findsNWidgets(2));
      expect(find.byType(Icon), findsNothing);
      expect(HomePanelAppLog.appLogRuntime.first.type, toast.$4, reason: 'toast ${toast.$1}');
      expect(HomePanelAppLog.appLogRuntime.first.content, toast.$3, reason: 'toast ${toast.$1}');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(toast.$3), findsNothing, reason: 'toast ${toast.$1} should auto close');
    }

    expect(HomePanelAppLog.appLogRuntime, hasLength(4));
  });

  testWidgets('a null message still logs and renders without throwing', (tester) async {
    await pump(tester);

    await HelperToast.info(null, duration: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(HomePanelAppLog.appLogRuntime.single.content, 'null');
    expect(find.text('null'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('several toasts can be stacked and dismissed together', (tester) async {
    await pump(tester);

    await HelperToast.error('First problem', duration: const Duration(seconds: 30));
    await HelperToast.warn('Second problem', duration: const Duration(seconds: 30));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('First problem'), findsOneWidget);
    expect(find.text('Second problem'), findsOneWidget);
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.type), ['WARN', 'ERROR'], reason: 'the newest entry comes first');

    toastification.dismissAll(delayForAnimation: false);
    await tester.pumpAndSettle();
    expect(find.text('First problem'), findsNothing);
    expect(find.text('Second problem'), findsNothing);
  });
}
