// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_pin.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_startup.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_view.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_controller.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_view.dart';
import 'package:kuraku/app/modules/widgets/widgets.dart';
import 'package:overlayment/overlayment.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_native_extensions/src/native/context.dart';
import 'package:window_manager/window_manager.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  final queue = GetQueue();
  bool failWrite = false;
  bool failQueuedSave = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async {
    values[key] = value;
    if (failWrite) throw StateError('Storage unavailable');
  }
  @override
  Future<void> save() async {
    if (failWrite) throw StateError('Storage unavailable');
    if (failQueuedSave) {
      failQueuedSave = false;
      scheduleMicrotask(() { unawaited(queue.add<void>(() async { throw const FileSystemException('Disk full'); })); });
    }
  }
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DropEvent implements DropEvent {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

class _WindowSettings extends AppSettingService {
  int homeRestores = 0;
  @override
  Future<void> setupStandaloneHomeWindow() async { homeRestores++; }
}

class _SlowPlayer extends StandalonePlayerController {
  final releasing = Completer<void>();

  @override
  Future<void> shutdown() async {
    await releasing.future;
    await super.shutdown();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pref = _Preferences();
  var preventClose = false;
  setUpAll(() {
    final dropContext = MockMessageChannelContext();
    dropContext.registerMockMethodCallHandler('DropManager', (_) async => null);
    dropContext.registerMockMethodCallHandler('DragManager', (_) async => null);
    setContextOverride(dropContext);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'), (_) async => 1,
    );
  });
  Future<void> submit(WidgetTester tester, String label) async {
    final action = find.widgetWithText(AppDialogAction, label);
    VoidCallback? onPressed() => action.evaluate().isNotEmpty
        ? tester.widget<AppDialogAction>(action).onPressed
        : tester.widget<FilledButton>(find.widgetWithText(FilledButton, label)).onPressed;
    await tester.runAsync(() async {
      final pending = (onPressed()! as Future<void> Function())();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(onPressed(), isNull);
      expect(tester.widget<AppDialogAction>(find.widgetWithText(AppDialogAction, 'Cancel')).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(action, findsOneWidget);
      await pending;
    });
    await tester.pumpAndSettle();
  }
  setUp(() {
    Get.testMode = true;
    preventClose = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async {
        if (call.method == 'setPreventClose') preventClose = call.arguments['isPreventClose'] as bool;
        return null;
      },
    );
    PackageInfo.setMockInitialValues(appName: 'KuraKu', packageName: 'kuraku', version: '1.2.3', buildNumber: '456', buildSignature: '');
    pref.values.clear();
    pref.failWrite = false;
    pref.failQueuedSave = false;
    Get.put<AppSettingService>(AppSettingService()..pref = pref);
  });
  tearDown(() {
    Get.reset(); Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), null,
    );
  });

  Future<void> revealPin(WidgetTester tester, {bool meta = true, bool alt = true}) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

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
    pref.failQueuedSave = true;
    await expectLater(AppPref.setAppPin(null, currentPin: '1234'), throwsA(isA<FileSystemException>()));
    expect(pref.values['_kAppPin'], beforeFailure);
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
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNWidgets(2));
    expect(find.text('New PIN (4–8 digits)'), findsOneWidget);
    await tester.enterText(find.byType(AppTextField).at(0), '12ab34');
    expect(tester.widget<AppTextField>(find.byType(AppTextField).at(0)).controller!.text, '1234');
    await tester.enterText(find.byType(AppTextField).at(1), '5678');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(AppPref.getAppPinEnabled(), isFalse);
    await tester.enterText(find.byType(AppTextField).at(1), '1234');
    await submit(tester, 'Save');
    expect(controller.appPinEnabled.value, isTrue);
    expect(_Settings().appPinEnabled.value, isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Change PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextField).at(0), '1234');
    await tester.enterText(find.byType(AppTextField).at(1), '5678');
    await tester.enterText(find.byType(AppTextField).at(2), '5678');
    await submit(tester, 'Save');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextField), '1234');
    await submit(tester, 'Disable');
    expect(find.text('Incorrect PIN.'), findsOneWidget);
    expect(AppPref.getAppPinEnabled(), isTrue);
    await tester.enterText(find.byType(AppTextField), '5678');
    await submit(tester, 'Disable');
    expect(AppPref.getAppPinEnabled(), isFalse);
    expect(controller.appPinEnabled.value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Gate hides PIN behind the exact shortcut, unlocks content and locks again for a new session', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    var builds = 0;
    var libraryInitializations = 0;
    Widget gate() => AppPinGate(child: AppStartup(
      initialize: () async {
        expect(preventClose, isFalse, reason: 'Library startup must remain closable before its own listener is ready');
        libraryInitializations++;
      },
      child: Builder(builder: (_) {
        builds++;
        return GetMaterialApp(home: const Text('Private content'));
      }),
    ));
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(libraryInitializations, 1);
    expect(find.text('Private content'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => AppPref.setAppPin('1234'));
    builds = 0;
    libraryInitializations = 0;
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(find.text('Private content'), findsNothing);
    expect(find.byType(StandalonePlayerView), findsOneWidget);
    expect(find.text('Open files'), findsOneWidget);
    expect(find.text('Drop videos here'), findsOneWidget);
    expect(find.descendant(of: find.byType(StandalonePlayerView),
      matching: find.text('Multiple videos become a playlist')), findsOneWidget);
    expect(find.ancestor(of: find.text('Drop videos here'), matching: find.byType(DottedBorder)), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.light);
    final lightLabelColor = tester.widget<Text>(find.text('Drop videos here')).style!.color!;
    final player = Get.find<StandalonePlayerController>();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
    expect(tester.widget<Text>(find.text('Drop videos here')).style!.color!.computeLuminance(), greaterThan(lightLabelColor.computeLuminance()));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.light);
    expect(Get.find<StandalonePlayerController>(), same(player));
    expect(Get.find<StandalonePlayerController>().isInitialized.value, isFalse);
    expect(libraryInitializations, 0);
    expect(Get.isRegistered<PlayerController>(), isFalse);
    expect(find.byType(AppTextField), findsNothing);
    expect(find.textContaining('PIN'), findsNothing);
    expect(find.text('KuraKu'), findsOneWidget);
    expect(find.text('v1.2.3+456'), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>()
      .having((image) => image.assetName, 'assetName', 'assets/images/app_icon.png'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 480));
    await tester.pumpAndSettle();
    expect(find.text('Open files').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpAndSettle();
    unawaited(Get.to(() => const Scaffold(body: Focus(autofocus: true, child: Text('Player overlay')))));
    await tester.pumpAndSettle();
    expect(find.text('Player overlay'), findsOneWidget);
    expect(find.ancestor(of: find.text('Player overlay'), matching: find.byType(DropRegion)), findsOneWidget);
    final dropRegion = tester.widget<DropRegion>(find.byType(DropRegion));
    dropRegion.onDropEnter!(_DropEvent());
    await tester.pumpAndSettle();
    expect(Get.find<StandalonePlayerController>().isDropHovering.value, isTrue);
    expect(tester.widget<AnimatedOpacity>(find.ancestor(
      of: find.text('Drop video or subtitle here'), matching: find.byType(AnimatedOpacity),
    )).opacity, 1);
    final dropHint = find.text('Drop video or subtitle here');
    expect(find.ancestor(of: dropHint, matching: find.byType(Material)), findsOneWidget);
    expect(find.ancestor(of: dropHint, matching: find.byType(DottedBorder)), findsOneWidget);
    expect(DefaultTextStyle.of(tester.element(dropHint)).style.decoration ?? TextDecoration.none, TextDecoration.none);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 240);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpAndSettle();
    dropRegion.onDropLeave!(_DropEvent());
    await tester.pumpAndSettle();
    await revealPin(tester);
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    Get.back();
    await tester.pumpAndSettle();
    await revealPin(tester, meta: false, alt: false);
    await revealPin(tester, alt: false);
    await revealPin(tester, meta: false);
    expect(find.byType(AppTextField), findsNothing);
    await revealPin(tester);
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    expect(tester.widget<AppTextField>(find.byType(AppTextField)).obscureText, isTrue);
    await revealPin(tester);
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AppTextField), findsNothing);
    expect(builds, 0);
    expect(find.text('Open files'), findsOneWidget);
    expect(libraryInitializations, 0);
    expect(Get.isRegistered<PlayerController>(), isFalse);
    await revealPin(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(find.byType(AppTextField), findsNothing);
    var playlistClosed = false;
    final playlist = Get.find<StandalonePlayerController>().openList().then((_) { playlistClosed = true; });
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    expect(find.text('Playlist'), findsOneWidget);
    expect(playlistClosed, isFalse);
    await revealPin(tester);
    await tester.enterText(find.byType(AppTextField), '9999');
    await submit(tester, 'Unlock');
    expect(find.text('Incorrect PIN.'), findsOneWidget);
    final pinInput = tester.widget<EditableText>(find.descendant(of: find.byType(AppPinForm), matching: find.byType(EditableText)));
    expect(pinInput.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(pinInput.controller.text, '999');
    expect(builds, 0);
    await tester.enterText(find.byType(AppTextField), '1234');
    await submit(tester, 'Unlock');
    expect(builds, 1);
    expect(find.text('Private content'), findsOneWidget);
    expect(find.text('Opening KuraKu, Please wait...'), findsNothing);
    expect(libraryInitializations, 1);
    expect(Get.isRegistered<StandalonePlayerController>(), isFalse);
    expect(Overlayment.count, 0);
    expect(playlistClosed, isTrue);
    await playlist;
    expect(Get.context, isNotNull);
    expect(Get.key.currentState, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(gate());
    await tester.pumpAndSettle();
    expect(find.byType(StandalonePlayerView), findsOneWidget);
    expect(find.text('Open files'), findsOneWidget);
    expect(libraryInitializations, 1);
    expect(find.byType(AppTextField), findsNothing);
    expect(find.text('Private content'), findsNothing);
    expect(builds, 1);
    final closeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async { closeCalls.add(call); return null; },
    );
    final listener = tester.state(find.byType(AppPinGate)) as WindowListener;
    listener.onWindowClose();
    listener.onWindowClose();
    await tester.pumpAndSettle();
    expect(Get.isRegistered<StandalonePlayerController>(), isFalse);
    expect(closeCalls.map((call) => call.method), ['setPreventClose', 'close']);
    expect(closeCalls.first.arguments, {'isPreventClose': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), null,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('locked player can rebuild while shutdown is pending', (tester) async {
    await tester.runAsync(() => AppPref.setAppPin('1234'));
    final player = Get.put<StandalonePlayerController>(_SlowPlayer(), permanent: true) as _SlowPlayer;
    final closeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async { closeCalls.add(call); return null; },
    );
    try {
      await tester.pumpWidget(const AppPinGate(child: Text('Private content')));
      await tester.pumpAndSettle();
      final listener = tester.state(find.byType(AppPinGate)) as WindowListener;
      listener.onWindowClose();
      await tester.pump();
      expect(closeCalls.map((call) => call.method), ['setPreventClose']);
      expect(closeCalls.single.arguments, {'isPreventClose': true});
      expect(Get.isRegistered<StandalonePlayerController>(), isFalse);
      final reassembly = tester.binding.reassembleApplication();
      await tester.pump();
      await reassembly;
      expect(tester.takeException(), isNull);
      expect(find.text('Private content'), findsNothing);
    } finally {
      player.releasing.complete();
      await tester.pumpAndSettle();
      expect(closeCalls.map((call) => call.method), ['setPreventClose', 'setPreventClose', 'close']);
      expect(closeCalls[1].arguments, {'isPreventClose': false});
      await tester.pumpWidget(const SizedBox.shrink());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), null,
      );
    }
  });

  testWidgets('leaving native fullscreen restores only the standalone home window', (tester) async {
    await Get.delete<AppSettingService>(force: true);
    final settings = _WindowSettings()..pref = pref;
    Get.put<AppSettingService>(settings);
    await tester.runAsync(() => AppPref.setAppPin('1234'));
    await tester.pumpWidget(const AppPinGate(child: SizedBox.shrink()));
    await tester.pumpAndSettle();
    final listener = tester.state(find.byType(AppPinGate)) as WindowListener;
    listener.onWindowLeaveFullScreen();
    await tester.pump();
    expect(settings.homeRestores, 1);
    Get.find<StandalonePlayerController>().isPlayerVisible.value = true;
    listener.onWindowLeaveFullScreen();
    expect(settings.homeRestores, 1);
    Get.find<StandalonePlayerController>().isPlayerVisible.value = false;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during PIN verification never initializes the library', (tester) async {
    await tester.runAsync(() => AppPref.setAppPin('1234'));
    var libraryInitializations = 0;
    final closeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async { closeCalls.add(call); return null; },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), null,
    ));
    await tester.pumpWidget(AppPinGate(child: AppStartup(
      initialize: () async { libraryInitializations++; },
      child: GetMaterialApp(home: const Text('Private content')),
    )));
    await tester.pumpAndSettle();
    await revealPin(tester);
    await tester.enterText(find.byType(AppTextField), '1234');
    final action = tester.widget<AppDialogAction>(find.widgetWithText(AppDialogAction, 'Unlock'));
    final listener = tester.state(find.byType(AppPinGate)) as WindowListener;
    await tester.runAsync(() async {
      final pending = (action.onPressed! as Future<void> Function())();
      listener.onWindowClose();
      listener.onWindowEnterFullScreen();
      await pending;
    });
    await tester.pumpAndSettle();
    expect(libraryInitializations, 0);
    expect(find.text('Private content'), findsNothing);
    expect(closeCalls.map((call) => call.method), ['setPreventClose', 'setPreventClose', 'close']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
