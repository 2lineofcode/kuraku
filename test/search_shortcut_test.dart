import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';

class _HomeController extends GetxController implements HomeController {
  int searchRequests = 0;
  String? selectedMenu;

  @override
  final currentMenuSelected = kMenuHome.obs;

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
  testWidgets('slash and Cmd F focus Search while preserving inputs and Chat shortcuts', (tester) async {
    final home = _HomeController();
    Get.put<HomeController>(home);
    final settings = AppSettingService();
    final focus = FocusNode();
    var chatSearchRequests = 0;
    addTearDown(() async {
      settings.onClose();
      for (final hotKey in hotKeyManager.registeredHotKeyList.toList()) {
        await hotKeyManager.unregister(hotKey);
      }
      focus.dispose();
      Get.reset();
    });
    await settings.setupHotkey();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => chatSearchRequests++},
      child: Focus(autofocus: true, child: TextField(focusNode: focus)),
    ))));
    await tester.pump();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash), isTrue);
    expect(home.searchRequests, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(home.searchRequests, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(home.selectedMenu, isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(home.searchRequests, 2);

    home.currentMenuSelected.value = kMenuChat;
    final beforeChatSearch = chatSearchRequests;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(home.searchRequests, 2);
    expect(chatSearchRequests, beforeChatSearch + 1);
    home.currentMenuSelected.value = kMenuHome;

    focus.requestFocus();
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash), isFalse);
    expect(focus.hasFocus, isTrue);
    expect(home.searchRequests, 2);
    home.selectedMenu = null;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(home.searchRequests, 2);
    expect(focus.hasFocus, isTrue);
    expect(home.selectedMenu, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
