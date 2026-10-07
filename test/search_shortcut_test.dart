import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/home_controller.dart';

class _HomeController extends GetxController implements HomeController {
  int searchRequests = 0;
  String? selectedMenu;

  @override
  Future<void> onMenuChange(String menu) async { selectedMenu = menu; }

  @override
  Future<void> onInit() async { super.onInit(); }

  @override
  void focusTopNavSearch() { searchRequests++; }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('slash opens Search but preserves typing and modified keys', (tester) async {
    final home = _HomeController();
    Get.put<HomeController>(home);
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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(focusNode: focus))));
    await tester.pump();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash), isTrue);
    expect(home.searchRequests, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(home.selectedMenu, isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(home.searchRequests, 1);

    focus.requestFocus();
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash), isFalse);
    expect(focus.hasFocus, isTrue);
    expect(home.searchRequests, 1);
    home.selectedMenu = null;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(home.selectedMenu, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
