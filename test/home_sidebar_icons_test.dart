import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_view.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> onMenuChange(String menu) async { currentMenuSelected.value = menu; }

  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

void main() {
  testWidgets('Hugeicons sidebar keeps its size and navigation in both layouts and themes', (tester) async {
    final home = Get.put<HomeController>(_Home());
    addTearDown(Get.reset);
    for (final brightness in Brightness.values) {
      for (final width in [65.0, 180.0]) {
        home.sideMenuWidth.value = width;
        await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: brightness), home: Scaffold(
          body: Row(children: [const HomeView().sideMenuContent()]),
        )));
        await tester.pumpAndSettle();
        expect(find.byType(HugeIcon), findsNWidgets(8));
        for (var index = 0; index < home.menus.length; index++) {
          final icon = find.byType(HugeIcon).at(index);
          expect(tester.getSize(icon), const Size(AppStyle.iconSize, AppStyle.iconSize));
          await tester.tap(icon);
          await tester.pumpAndSettle();
          expect(home.currentMenuSelected.value, home.menus[index]['name']);
        }
        final settings = find.byType(HugeIcon).last;
        expect(tester.widget<HugeIcon>(settings).icon, HugeIcons.strokeRoundedSettings01);
        expect(tester.getTopLeft(settings).dy, greaterThan(tester.getBottomLeft(find.byType(HugeIcon).at(6)).dy));
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(home.currentMenuSelected.value, kMenuSetting);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
