import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_surfaces.dart';
import 'package:kuraku/app/utils/r18_updater.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  int updateChecks = 0;
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async { refreshes++; }
  @override
  Future<void> saveRelapseLimit() async { saves++; }
  @override
  Future<void> checkForAppUpdate() async { updateChecks++; }
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
    PackageInfo.setMockInitialValues(appName: 'kuraku', packageName: 'kuraku', version: '1.2.3', buildNumber: '', buildSignature: '');
    Get.testMode = true;
    final service = Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    final home = Get.put<HomeController>(_Home());
    final controller = _Settings();
    Get.put<PageSettingsController>(controller);
    await controller.refreshAppVersion();
    expect(controller.appVersion.value, '1.2.3');
    PackageInfo.setMockInitialValues(appName: 'kuraku', packageName: 'kuraku', version: '1.2.3', buildNumber: '20261008.60', buildSignature: '');
    await controller.refreshAppVersion();
    expect(controller.appVersion.value, '1.2.3+20261008.60');
    controller.totalLibrary.value = 2;
    controller.totalVideos.value = 485;
    controller.totalAlbums.value = 3;
    controller.totalImages.value = 112;
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
          expect(tester.getCenter(find.text('Storage Usage'.tr)).dy, closeTo(tester.getCenter(find.text('Refresh'.tr)).dy, 1));
          final storageHeading = find.ancestor(of: find.text('Storage Usage'.tr), matching: find.byType(AppSectionHeading));
          final refresh = find.widgetWithText(AppButton, 'Refresh'.tr);
          expect(tester.getRect(refresh).right, closeTo(tester.getRect(storageHeading).right, 1));
          expect(tester.getTopLeft(find.text('Application Info'.tr)).dy, lessThan(tester.getTopLeft(find.text('Appearance'.tr)).dy));
          expect(find.text('Personalize your experience and manage your library.'.tr), findsNothing);
          if (width == 1100) {
            final theme = find.byType(AppDropdown<AppTheme>);
            final languageControl = find.byWidgetPredicate((widget) => widget is AppDropdown<String> && widget.value == language);
            expect(tester.getTopLeft(theme).dx, tester.getTopLeft(languageControl).dx);
            expect(tester.getSize(theme).width, lessThanOrEqualTo(320));
          }
          expect(find.text('1.2.3+20261008.60'), findsOneWidget);
          expect(find.text('Check for Updates'.tr), findsOneWidget);
          expect(find.text('Total Albums'.tr), findsOneWidget);
          expect(find.text('Total Images'.tr), findsOneWidget);
          expect(find.text('112'), findsOneWidget);
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
    controller.appUpdateChecking.value = true;
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Checking for updates...'.tr)).onPressed, isNull);
    controller.appUpdateChecking.value = false;
    controller.appUpdateError.value = true;
    controller.appUpdateStatus.value = 'The update check timed out. Please try again.'.tr;
    await tester.pumpAndSettle();
    expect(find.text('The update check timed out. Please try again.'.tr), findsOneWidget);
    await tester.tap(find.text('Check for Updates'.tr));
    expect(controller.updateChecks, 1);
    await tester.tap(find.byWidgetPredicate((widget) => widget is Switch && widget.key != const ValueKey('app-pin-switch')));
    await tester.pumpAndSettle();
    expect(home.sideMenuWidth.value, 65);
    expect(AppPref.getAppHideSideMenu(), isTrue);
    final player = find.byWidgetPredicate((widget) => widget is AppDropdown<String> && widget.value == 'In App');
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
    controller.isLoadingStorage.value = true;
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Refresh')).onPressed, isNull);
    controller.isLoadingStorage.value = false;
    await tester.pump();
    await tester.ensureVisible(find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    expect(controller.refreshes, refreshes + 1);
    expect(tester.takeException(), isNull);
    addTearDown(() { R18Updater.busy.value = false; R18Updater.status.value = ''; R18Updater.progress.value = -1; });
    R18Updater.busy.value = true;
    R18Updater.status.value = 'Importing and validating R18...'.tr;
    R18Updater.progress.value = -1;
    await tester.pump();
    final update = find.ancestor(of: find.text('Update R18 DB'.tr), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(update).onTap, isNull);
    expect(find.byWidgetPredicate((widget) => widget is LinearProgressIndicator && widget.semanticsLabel == 'Update R18 DB'.tr), findsOneWidget);
    R18Updater.busy.value = false;
    R18Updater.status.value = 'R18 update failed. Please retry.'.tr;
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(update).onTap, isNotNull);
    expect(find.text('R18 update failed. Please retry.'.tr), findsOneWidget);
    expect(find.text('Utilities'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.appLogMode.value = true;
    await tester.pumpAndSettle();
    final level = find.byType(AppDropdown<String>);
    expect(level, findsOneWidget);
    await tester.tap(level);
    await tester.pump();
    expect(find.byType(MenuItemButton), findsNWidgets(5));
    await tester.tap(find.widgetWithText(MenuItemButton, 'ERROR'));
    await tester.pumpAndSettle();
    expect(controller.appLogLevelSelected.value, 'ERROR');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
