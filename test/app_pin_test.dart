import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/core/app_pin.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  final queue = GetQueue();
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
  final pref = _Preferences();
  Future<void> submit(WidgetTester tester, String label) async {
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
    await tester.runAsync(() async {
      final pending = (button.onPressed! as Future<void> Function())();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, label)).onPressed, isNull);
      await pending;
    });
    await tester.pumpAndSettle();
  }
  setUp(() {
    Get.testMode = true;
    pref.values.clear();
    pref.failWrite = false;
    Get.put<AppSettingService>(AppSettingService()..pref = pref);
  });
  tearDown(() { Get.reset(); Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });

  test('PIN defaults off, hashes with salt, requires current PIN and rolls back failed saves', () async {
    expect(AppPref.getAppPinEnabled(), isFalse);
    for (final pin in ['', '123', '123456789', 'abcd', '12 34', '1234\n']) {
      await expectLater(AppPref.setAppPin(pin), throwsArgumentError);
    }
    pref.values['_kAppPin'] = {
      'salt': 'AAECAwQFBgcICQoLDA0ODw==',
      'hash': 'nznZxxwixMRZvCy6zG104hhBhdZx2R8KNKaDRBOghJ0=',
    };
    final watch = Stopwatch()..start();
    expect(await AppPref.verifyAppPin('1234'), isTrue);
    print('Existing PIN verification: ${watch.elapsedMilliseconds}ms');
    expect(await AppPref.setAppPin(null, currentPin: '1234'), isTrue);
    expect(await AppPref.setAppPin('1234'), isTrue);
    final first = Map<String, String>.from(pref.values['_kAppPin'] as Map);
    expect(first.keys.toSet(), {'salt', 'hash'});
    expect(first.values, isNot(contains('1234')));
    expect(await AppPref.verifyAppPin('9999'), isFalse);
    expect(await AppPref.verifyAppPin('1234'), isTrue);
    expect(await AppPref.setAppPin('5678', currentPin: '9999'), isFalse);
    expect(await AppPref.setAppPin(null), isFalse);
    expect(pref.values['_kAppPin'], first);
    expect(await AppPref.setAppPin('1234', currentPin: '1234'), isTrue);
    expect(pref.values['_kAppPin']['salt'], isNot(first['salt']));
    expect(pref.values['_kAppPin']['hash'], isNot(first['hash']));
    final beforeFailure = pref.values['_kAppPin'];
    pref.failWrite = true;
    await expectLater(AppPref.setAppPin(null, currentPin: '1234'), throwsStateError);
    expect(pref.values['_kAppPin'], beforeFailure);
    pref.failWrite = false;
    expect(await AppPref.setAppPin('5678', currentPin: '1234'), isTrue);
    expect(await AppPref.verifyAppPin('1234'), isFalse);
    expect(await AppPref.verifyAppPin('5678'), isTrue);
    for (var i = 0; i < 5; i++) { expect(await AppPref.verifyAppPin(''), isFalse); }
    expect(AppPref.appPinCoolingDown, isTrue);
    expect(await AppPref.verifyAppPin('5678'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Settings enables, changes and disables PIN with confirmation and current PIN', (tester) async {
    // Starting with no lock also clears the previous session's cooldown.
    await AppPref.setAppPin(null);
    final controller = Get.put<PageSettingsController>(_Settings());
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: Builder(builder: (context) {
      AppColor.dependOn(context);
      return const PageSettingsView().buildPinSetting();
    }))));
    final toggle = find.byKey(const ValueKey('app-pin-switch'));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '12ab34');
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '1234');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(AppPref.getAppPinEnabled(), isFalse);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await submit(tester, 'Save');
    expect(controller.appPinEnabled.value, isTrue);
    expect(_Settings().appPinEnabled.value, isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Change PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await tester.enterText(find.byType(TextField).at(2), '5678');
    await submit(tester, 'Save');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await submit(tester, 'Disable');
    expect(find.text('Incorrect PIN.'), findsOneWidget);
    expect(AppPref.getAppPinEnabled(), isTrue);
    await tester.enterText(find.byType(TextField), '5678');
    await submit(tester, 'Disable');
    expect(AppPref.getAppPinEnabled(), isFalse);
    expect(controller.appPinEnabled.value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Gate opens content directly after unlock and locks again for a new session', (tester) async {
    var builds = 0;
    Widget gate() => AppPinGate(child: Builder(builder: (_) {
        builds++;
        return const MaterialApp(home: Text('Private content'));
      }));
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.text('Private content'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => AppPref.setAppPin('1234'));
    builds = 0;
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(find.text('Private content'), findsNothing);
    expect(await Navigator.of(tester.element(find.byType(TextField))).maybePop(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(builds, 0);
    await tester.enterText(find.byType(TextField), '9999');
    await submit(tester, 'Unlock');
    expect(find.text('Incorrect PIN.'), findsOneWidget);
    expect(builds, 0);
    await tester.enterText(find.byType(TextField), '1234');
    await submit(tester, 'Unlock');
    expect(builds, 1);
    expect(find.text('Private content'), findsOneWidget);
    expect(find.text('Opening JavIt, Please wait...'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(find.text('Unlock JavIt'), findsOneWidget);
    expect(find.text('Private content'), findsNothing);
    expect(builds, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
