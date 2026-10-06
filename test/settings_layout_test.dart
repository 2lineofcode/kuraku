import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/core/app_translations.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  int refreshes = 0;
  int saves = 0;
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async { refreshes++; }
  @override
  Future<void> saveRelapseLimit() async { saves++; }
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
}

void main() {
  testWidgets('Settings adapts to window sizes and keeps controls connected', (tester) async {
    Get.testMode = true;
    final service = Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    final home = Get.put<HomeController>(_Home());
    final controller = _Settings();
    Get.put<PageSettingsController>(controller);
    controller.totalLibrary.value = 2;
    controller.totalVideos.value = 485;
    controller.totalFilesize.value = 861151872778;
    controller.lastRelapse.value = 'Oct, 3 2026 11:12';
    controller.r18TotalVideo.value = 1907649;
    controller.dbR18Version.value = 20260929;
    controller.semanticReady.value = true;
    controller.semanticEmbeddingCount.value = 420;
    controller.semanticMissingCount.value = 65;
    controller.storageList.add(StorageUsage(label: 'Macintosh HD', path: '/', totalBytes: 500000000000, freeBytes: 59000000000, isExternal: false));
    final boundary = GlobalKey();
    addTearDown(() { service.onClose(); Get.reset(); Get.clearTranslations(); });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const output = String.fromEnvironment('SETTINGS_QA_PATH');
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('VisualQA');
        loader.addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    for (final language in ['id', 'en']) {
      Get.locale = Locale(language);
      controller.appLanguage.value = language;
      for (final dark in [false, true]) {
        controller.appTheme.value = dark ? AppTheme.dark : AppTheme.light;
        for (final width in [1100.0, 700.0, 360.0]) {
          tester.view.physicalSize = Size(width, 1500);
          await tester.pumpWidget(GetMaterialApp(
            translations: AppTranslations(), locale: Locale(language),
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, colorSchemeSeed: const Color(0xff7357b5), fontFamily: font.isEmpty ? null : 'VisualQA'),
            home: Builder(builder: (context) {
              AppColor.dependOn(context);
              return Scaffold(backgroundColor: AppColor.body,
                body: RepaintBoundary(key: boundary, child: ColoredBox(color: AppColor.body, child: const PageSettingsView())),
              );
            }),
          ));
          await tester.pumpAndSettle();
          expect(Get.locale, Locale(language));
          expect(find.text('Appearance'.tr), findsOneWidget);
          expect(find.text('Playback & Search'.tr), findsOneWidget);
          expect(find.text('Utilities'.tr), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'language=$language width=$width dark=$dark');
          if (output.isNotEmpty && width == 1100) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$output-$language-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    }
    tester.view.physicalSize = const Size(1100, 1500);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(home.sideMenuWidth.value, 65);
    expect(AppPref.getAppHideSideMenu(), isTrue);
    final player = find.byWidgetPredicate((widget) => widget is DropdownButton<String> && widget.value == 'In App');
    await tester.tap(player);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default System').last);
    await tester.pumpAndSettle();
    expect(AppPref.getDefaultPlayer(), 'Default System');
    final seek = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.controller == controller.tecPlayerSeekShort);
    await tester.enterText(seek, '9');
    expect(AppPref.getPlayerSeekShort(), 9);
    await tester.tap(find.byTooltip('Save daily limit (0 blocks playback)'));
    expect(controller.saves, 1);
    final refreshes = controller.refreshes;
    await tester.ensureVisible(find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    expect(controller.refreshes, refreshes + 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
