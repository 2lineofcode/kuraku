import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  bool failWrite = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async {
    values[key] = value;
    if (failWrite) throw StateError('Storage unavailable');
  }
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

void main() {
  testWidgets('Theme dropdown persists choices, follows system and resolves schedule boundaries', (tester) async {
    Get.testMode = true;
    final pref = _Preferences();
    final service = Get.put<AppSettingService>(AppSettingService()..pref = pref);
    addTearDown(() { service.onClose(); Get.reset(); });
    expect(AppPref.getAppTheme(), AppTheme.dark);
    pref.values['_kAppDarkMode'] = false;
    expect(AppPref.getAppTheme(), AppTheme.light);
    pref.values['_kAppTheme'] = 'invalid';
    expect(AppPref.getAppTheme(), AppTheme.light);
    pref.values.remove('_kAppTheme');
    for (final (hour, minute, expected) in [
      (0, 0, ThemeMode.dark), (5, 59, ThemeMode.dark), (6, 0, ThemeMode.light),
      (16, 59, ThemeMode.light), (17, 0, ThemeMode.dark), (23, 59, ThemeMode.dark),
    ]) {
      expect(AppTheme.schedule.resolve(DateTime(2026, 10, 3, hour, minute)), expected);
    }
    final controller = Get.put<PageSettingsController>(_Settings());
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(GetMaterialApp(
      themeMode: AppPref.getAppTheme().resolve(), theme: ThemeData.light(), darkTheme: ThemeData.dark(),
      home: Scaffold(body: Builder(builder: (context) {
        AppColor.dependOn(context);
        return const PageSettingsView().buildThemeSetting();
      })),
    ));
    expect(find.text('Theme'), findsOneWidget);
    for (final theme in [AppTheme.system, AppTheme.schedule, AppTheme.dark, AppTheme.light]) {
      await tester.tap(find.byType(DropdownButton<AppTheme>));
      await tester.pumpAndSettle();
      final options = tester.widget<DropdownButton<AppTheme>>(find.byType(DropdownButton<AppTheme>)).items!;
      expect(options.map((item) => item.value), AppTheme.values);
      final label = theme == AppTheme.schedule ? 'Auto Schedule (06-17 light | 17-06 dark)' : theme.label;
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(controller.appTheme.value, theme);
      expect(AppPref.getAppTheme(), theme);
      expect(pref.read<String>('_kAppTheme'), theme.name);
      expect(Get.rootController.themeMode, theme.resolve());
      expect(tester.takeException(), isNull);
      if (theme == AppTheme.system) {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          await tester.pumpAndSettle();
          expect(Get.isDarkMode, brightness == Brightness.dark);
        }
      }
    }
    final recreated = _Settings();
    expect(recreated.appTheme.value, AppTheme.light);
    recreated.onClose();
    pref.failWrite = true;
    await expectLater(AppPref.setAppTheme(AppTheme.dark), throwsStateError);
    expect(AppPref.getAppTheme(), AppTheme.light);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
