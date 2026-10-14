import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/modules/widgets/widget_keyboard_shortcuts.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:kuraku/app/utils/helper_opener.dart';

void main() {
  testWidgets('shortcut panel keeps all entries, scrolls and closes in both themes and languages', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() { Get.reset(); Get.clearTranslations(); });
    var closed = false;
    for (final language in ['en', 'id']) {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(800, 1100), const Size(320, 480)]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(GetMaterialApp(
            translations: AppTranslations(), locale: Locale(language), theme: AppStyle.theme(brightness),
            home: Scaffold(body: Center(child: SizedBox(width: 480,
              child: KeyboardShortcutsPanel(onClose: () => closed = true)))),
          ));
          await tester.pumpAndSettle();
          expect(find.text('Keyboard Shortcuts'.tr), findsOneWidget);
          expect(find.text('Go to Home'.tr), findsOneWidget);
          expect(find.text('Open relapse panel'.tr), findsOneWidget);
          expect(find.text('Open Keyboard Shortcuts'.tr), findsOneWidget);
          expect(tester.getSize(find.byType(KeyboardShortcutsPanel)).height, lessThanOrEqualTo(size.height * .85));
          for (final entry in [('Player', 'Enable/disable bottom controls'), ('Pages', 'Run query'), ('Chat', 'Stop response')]) {
            await tester.tap(find.descendant(of: find.byType(CupertinoSlidingSegmentedControl<String>), matching: find.text(entry.$1.tr)));
            await tester.pumpAndSettle();
            expect(find.text(entry.$2.tr), findsOneWidget);
            expect(find.text('= × 2'), findsNothing);
            expect(find.text('Go to Home'.tr), findsNothing);
            await tester.ensureVisible(find.text(entry.$2.tr));
            expect(find.text(entry.$2.tr).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.tap(find.descendant(of: find.byType(CupertinoSlidingSegmentedControl<String>), matching: find.text('App'.tr)));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Close dialog/panel'.tr));
          expect(find.text('Close dialog/panel'.tr).hitTestable(), findsOneWidget);
          expect(find.byTooltip('Close'.tr).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close'.tr));
          expect(closed, isTrue);
          closed = false;
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          expect(closed, isTrue);
          closed = false;
        }
      }
    }
  });

  testWidgets('Cmd slash opens from an input, prevents duplicates and works again after closing', (tester) async {
    final settings = AppSettingService();
    final focus = FocusNode();
    addTearDown(() async {
      settings.onClose();
      for (final hotKey in hotKeyManager.registeredHotKeyList.toList()) {
        await hotKeyManager.unregister(hotKey);
      }
      focus.dispose();
      Get.reset();
    });
    await settings.setupHotkey();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextField(focusNode: focus))));
    focus.requestFocus();
    await tester.pump();
    Future<void> open() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }
    await open();
    expect(find.byType(KeyboardShortcutsPanel), findsOneWidget);
    await open();
    expect(find.byType(KeyboardShortcutsPanel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsPanel), findsNothing);
    await open();
    expect(find.byType(KeyboardShortcutsPanel), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings opener shows a centered panel that Escape dismisses', (tester) async {
    addTearDown(() { Get.reset(); Get.clearTranslations(); });
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: HelperOpener.openKeyboardShortcuts, child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(KeyboardShortcutsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(KeyboardShortcutsPanel), findsNothing);
  });
}
