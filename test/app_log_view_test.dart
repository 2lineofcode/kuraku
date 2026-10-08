import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/core/app_translations.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:toastification/toastification.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> refreshAppVersion() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

void main() {
  testWidgets('app logs adapt, filter, copy, update live and keep toolbar visible while scrolling', (tester) async {
    Get.testMode = true;
    final settings = Get.put(AppSettingService()..pref = _Preferences());
    final controller = Get.put<PageSettingsController>(_Settings());
    controller.appLogMode.value = true;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() { controller.onClose(); settings.onClose(); HomePanelAppLog.clear(); Get.reset(); Get.clearTranslations(); });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final entries = [
      AppLogRuntime(type: 'WARNING', content: 'Could not access /Volumes/Data. Skipping this library.', createdAt: '2026-10-08 14:42:42'),
      AppLogRuntime(type: 'DEBUG', content: 'Database ready', createdAt: 'invalid-date'),
      AppLogRuntime(content: 'Unknown entry'),
      ...List.generate(100, (index) => AppLogRuntime(type: 'INFO', content: 'Entry $index', createdAt: '2026-10-08 14:42:41')),
    ];
    for (final language in ['en', 'id']) {
      for (final brightness in Brightness.values) {
        for (final width in [900.0, 320.0]) {
          tester.view.physicalSize = Size(width, 600);
          controller.appLogKeyword.value = '';
          controller.tecAppLogFilter.clear();
          controller.appLogLevelSelected.value = 'ALL';
          HomePanelAppLog.appLogRuntime.assignAll(entries);
          await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(
            theme: AppStyle.theme(brightness), translations: AppTranslations(), locale: Locale(language),
            home: const Scaffold(body: PageSettingsView()),
          )));
          await tester.pumpAndSettle();
          expect(find.text('WARN'), findsOneWidget);
          expect(find.text('invalid-date'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(find.text('Entry 99'), findsNothing);
          await tester.scrollUntilVisible(find.text('Entry 99'), 300, scrollable: find.byType(Scrollable).last);
          expect(find.byType(CupertinoTextField).hitTestable(), findsOneWidget);
          expect(find.text('Clear'.tr).hitTestable(), findsOneWidget);
          await tester.enterText(find.byType(CupertinoTextField), 'Database');
          await tester.pumpAndSettle();
          expect(find.text('Database ready'), findsOneWidget);
          expect(find.text(entries.first.content!), findsNothing);
          await tester.tap(find.text('Database ready'));
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(copied, 'Database ready');
          toastification.dismissAll();
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(CupertinoTextField), '');
          await tester.tap(find.byType(AppDropdown<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text('WARN')));
          await tester.pumpAndSettle();
          expect(controller.appLogLevelSelected.value, 'WARN');
          expect(find.text(entries.first.content!), findsOneWidget);
          expect(find.text('Database ready'), findsNothing);
          await tester.enterText(find.byType(CupertinoTextField), 'missing');
          await tester.pumpAndSettle();
          expect(find.text('No matching items'.tr), findsOneWidget);
          await HomePanelAppLog.add('WARNING', 'missing drive');
          await tester.pumpAndSettle();
          expect(find.text('missing drive'), findsOneWidget);
          await tester.tap(find.text('Clear'.tr));
          await tester.pumpAndSettle();
          expect(HomePanelAppLog.appLogRuntime, isEmpty);
          expect(find.text('No app logs'.tr), findsOneWidget);
        }
      }
    }
    await tester.tap(find.byTooltip('Back'.tr));
    expect(controller.appLogMode.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
