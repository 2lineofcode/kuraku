import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:kuraku/app/core/const.dart';
import 'package:kuraku/app/modules/home/home_binding.dart';
import 'package:kuraku/app/modules/home/home_view.dart';
import 'package:kuraku/app/modules/img_viewer/img_viewer_binding.dart';
import 'package:kuraku/app/modules/img_viewer/img_viewer_controller.dart';
import 'package:kuraku/app/modules/img_viewer/img_viewer_view.dart';
import 'package:kuraku/app/modules/player/player_binding.dart';
import 'package:kuraku/app/modules/player/player_view.dart';
import 'package:kuraku/app/routes/app_pages.dart';

void main() {
  test('route names are unique constants and the app starts on home', () {
    expect(Routes.ROOT, '/');
    expect(Routes.HOME, '/home');
    expect(Routes.PLAYER, '/player');
    expect(Routes.IMG_VIEWER, '/img-viewer');
    expect(AppPages.INITIAL, Routes.HOME);

    final names = AppPages.routes.map((page) => page.name).toList();
    expect(names, [Routes.HOME, Routes.PLAYER, Routes.IMG_VIEWER]);
    expect(names.toSet(), hasLength(names.length));
    expect(names.every((name) => name.startsWith('/')), isTrue);
  });

  test('every route builds its view and ships the matching binding', () {
    final pages = {for (final page in AppPages.routes) page.name: page};

    expect(pages[Routes.HOME]!.page(), isA<HomeView>());
    expect(pages[Routes.PLAYER]!.page(), isA<PlayerView>());
    expect(pages[Routes.IMG_VIEWER]!.page(), isA<ImgViewerView>());

    expect(pages[Routes.HOME]!.binding, isA<HomeBinding>());
    expect(pages[Routes.PLAYER]!.binding, isA<PlayerBinding>());
    expect(pages[Routes.IMG_VIEWER]!.binding, isA<ImgViewerBinding>());
    expect(AppPages.routes.every((page) => page.binding != null), isTrue);
  });

  testWidgets('the image viewer binding provides a controller lazily', (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();

    ImgViewerBinding().dependencies();

    final controller = Get.find<ImgViewerController>();
    expect(controller, isA<ImgViewerController>());
    expect(Get.find<ImgViewerController>(), same(controller), reason: 'the binding must not rebuild the controller');

    await Get.delete<ImgViewerController>();
  });

  test('the shared date formats match the values stored in the database', () {
    final moment = DateTime(2026, 3, 4, 15, 6, 7);

    expect(kYMd, 'yyyy-MM-dd');
    expect(kMdY, 'MMM dd, yyyy');
    expect(kHms, 'HH:mm:ss');
    expect(kFull, 'yyyy-MM-dd HH:mm:ss');

    expect(DateFormat(kYMd).format(moment), '2026-03-04');
    expect(DateFormat(kMdY).format(moment), 'Mar 04, 2026');
    expect(DateFormat(kHms).format(moment), '15:06:07');
    expect(DateFormat(kFull).format(moment), '2026-03-04 15:06:07');
    expect(DateFormat(kFull).parse('2026-03-04 15:06:07'), moment);
    expect(DateFormat(kFull).format(moment).startsWith(DateFormat(kYMd).format(moment)), isTrue);
  });
}
