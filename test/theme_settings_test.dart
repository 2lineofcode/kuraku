import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';

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
    await service.setupHotkey();
    addTearDown(() async {
      for (final hotKey in hotKeyManager.registeredHotKeyList.toList()) {
        await hotKeyManager.unregister(hotKey);
      }
    });
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(GetMaterialApp(
      themeMode: AppPref.getAppTheme().resolve(), theme: AppStyle.theme(Brightness.light), darkTheme: AppStyle.theme(Brightness.dark),
      home: Scaffold(body: Builder(builder: (context) {
        AppColor.dependOn(context);
        return Column(children: [const PageSettingsView().buildThemeSetting(), const PageSettingsView().buildAccentSetting()]);
      })),
    ));
    expect(find.text('Theme'), findsOneWidget);
    for (final theme in [AppTheme.system, AppTheme.schedule, AppTheme.dark, AppTheme.light]) {
      await tester.tap(find.byType(AppDropdown<AppTheme>));
      await tester.pumpAndSettle();
      final options = tester.widget<AppDropdown<AppTheme>>(find.byType(AppDropdown<AppTheme>)).items;
      expect(options.map((item) => item.value), AppTheme.values);
      final label = theme.label;
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
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(Get.isDarkMode, theme == AppTheme.dark);
      expect(AppPref.getAppTheme(), theme);
      expect(controller.appTheme.value, theme);
    }
    final recreated = _Settings();
    expect(recreated.appTheme.value, AppTheme.light);
    recreated.onClose();
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      Get.changeThemeMode(mode);
      await tester.pumpAndSettle();
      expect(AppColor.accent, AppColor.selected);
    }
    await tester.enterText(find.byType(AppTextField), '#205080');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), 0xff205080);
    final restored = _Settings();
    expect(restored.tecAppAccent.text, '205080');
    restored.onClose();
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      Get.changeThemeMode(mode);
      await tester.pumpAndSettle();
      expect(AppColor.accent, const Color(0xff205080));
      expect(AppColor.selected, const Color(0xff205080));
      final a = AppColor.accent.computeLuminance(), b = AppColor.onAccent.computeLuminance();
      expect((a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)), greaterThanOrEqualTo(4.5));
    }
    await tester.enterText(find.byType(AppTextField), 'invalid');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Use RRGGBB or AARRGGBB HEX'), findsOneWidget);
    expect(AppPref.getAppAccent(), 0xff205080);
    pref.failWrite = true;
    await tester.enterText(find.byType(AppTextField), 'FFFFFF');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), 0xff205080);
    expect(AppColor.accent, const Color(0xff205080));
    expect(AppColor.selected, const Color(0xff205080));
    expect(find.text('Could not save appearance. Please retry.'), findsOneWidget);
    pref.failWrite = false;
    await tester.tap(find.byTooltip('Pick accent color'));
    await tester.pumpAndSettle();
    expect(find.text('Opacity'), findsOneWidget);
    expect(tester.widgetList<ColorPickerSlider>(find.byType(ColorPickerSlider)).map((slider) => slider.trackType), [TrackType.hue, TrackType.alpha]);
    tester.widget<ColorPickerArea>(find.byType(ColorPickerArea)).onColorChanged(HSVColor.fromColor(const Color(0x80205080)));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), 0xff205080);
    await tester.tap(find.byTooltip('Pick accent color'));
    await tester.pumpAndSettle();
    tester.widget<ColorPickerArea>(find.byType(ColorPickerArea)).onColorChanged(HSVColor.fromColor(const Color(0x80205080)));
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), 0x80205080);
    expect(AppColor.selected, const Color(0x80205080));
    final transparentRestored = _Settings();
    expect(transparentRestored.tecAppAccent.text, '80205080');
    transparentRestored.onClose();
    await tester.enterText(find.byType(AppTextField), '#00000000');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), 0);
    expect(AppColor.accent.a, 0);
    final fullyTransparentRestored = _Settings();
    expect(fullyTransparentRestored.tecAppAccent.text, '00000000');
    fullyTransparentRestored.onClose();
    await tester.tap(find.byTooltip('Reset accent color'));
    await tester.pumpAndSettle();
    expect(AppPref.getAppAccent(), isNull);
    expect(controller.tecAppAccent.text, isEmpty);
    expect(AppColor.accent, AppColor.selected);
    pref.values['_kAppAccent'] = 'invalid';
    expect(AppStyle.theme(Brightness.dark).colorScheme.primary, AppColor.defaultAccent(Brightness.dark));
    await expectLater(AppPref.setAppAccent(-1), throwsArgumentError);
    await expectLater(AppPref.setAppAccent(0x100000000), throwsArgumentError);
    pref.values.remove('_kAppAccent');
    expect(tester.takeException(), isNull);
    pref.failWrite = true;
    await expectLater(AppPref.setAppTheme(AppTheme.dark), throwsStateError);
    expect(AppPref.getAppTheme(), AppTheme.light);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
