import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/player/player_controller.dart';
import 'package:javit/app/modules/player/player_controls.dart';
import 'package:javit/app/utils/semantic_search_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:overlayment/overlayment.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NativePlayer implements NativePlayer {
  final commands = <List<String>>[];
  final properties = <String, String>{};
  bool failRotation = false;
  bool failZoom = false;

  @override
  Future<void> command(List<String> command, {bool waitForInitialization = true}) async {
    if (failRotation) throw StateError('Rotation failed');
    commands.add(command);
  }

  @override
  Future<void> setProperty(String property, String value, {bool waitForInitialization = true}) async {
    if (property == 'video-zoom' && failZoom) throw StateError('Zoom failed');
    properties[property] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  final NativePlayer platform;

  _Player(this.platform);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Permanent player only blocks visual search while visible', (tester) async {
    Get.put(AppSettingService()..pref = _Preferences());
    addTearDown(Get.reset);
    final controller = Get.put(PlayerController(), permanent: true);
    expect(SemanticSearchService.playbackActive, isFalse);
    SemanticSearchService.beginPlayback();
    controller.isPlayerVisible.value = false;
    expect(SemanticSearchService.playbackActive, isTrue);
    SemanticSearchService.endPlayback();
    controller.isPlayerVisible.value = true;
    expect(SemanticSearchService.playbackActive, isTrue);
    controller.isPlayerVisible.value = true;
    controller.isPlayerVisible.value = false;
    expect(SemanticSearchService.playbackActive, isFalse);
    SemanticSearchService.beginPlayback();
    controller.isPlayerVisible.value = true;
    controller.isPlayerVisible.value = false;
    expect(SemanticSearchService.playbackActive, isTrue);
    SemanticSearchService.endPlayback();
    expect(SemanticSearchService.playbackActive, isFalse);
    controller.isPlayerVisible.value = true;
    await Get.delete<PlayerController>(force: true);
    await tester.pump();
    expect(SemanticSearchService.playbackActive, isFalse);
  });

  testWidgets('trackpad pinch zooms video, clamps scale and resets without changing playback', (tester) async {
    Get.put(AppSettingService()..pref = _Preferences());
    addTearDown(Get.reset);
    final native = _NativePlayer();
    final controller = PlayerController()..player = _Player(native);
    controller.currentVideo.value = Videos(videoCode: '', title: 'Test', videoPath: '');
    controller.infoAnimationController = AnimationController(vsync: tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlayerControls(controller: controller, videoState: VideoState()))));
    await tester.pumpAndSettle();
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    const center = Offset(400, 250);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(pointer.panZoomUpdate(center, scale: 1.1));
    await tester.sendEventToBinding(pointer.panZoomUpdate(center, scale: 2));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(controller.videoZoom.value, 2);
    expect(double.parse(native.properties['video-zoom']!), closeTo(1, 0.0001));
    expect(controller.isPlaying.value, isFalse);
    await tester.tap(find.text('Zoom 200% · Reset'));
    await tester.pumpAndSettle();
    expect(controller.videoZoom.value, 1);
    expect(native.properties['video-zoom'], '0.0');

    await controller.setVideoZoom(20);
    expect(controller.videoZoom.value, 4);
    await controller.setVideoZoom(double.nan);
    expect(controller.videoZoom.value, 4);
    native.failZoom = true;
    await controller.setVideoZoom(2);
    expect(controller.videoZoom.value, 4);
    native.failZoom = false;
    await Future.wait([controller.setVideoZoom(3), controller.setVideoZoom(0.5)]);
    expect(controller.videoZoom.value, 1);
    expect(native.properties['video-zoom'], '0.0');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.infoAnimationController.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('player shortcuts recover from empty scopes and respect active overlays and routes', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(AppSettingService()..pref = _Preferences());
    addTearDown(Get.reset);
    final controller = PlayerController()..player = _Player(_NativePlayer());
    controller.currentVideo.value = Videos(videoCode: '', title: 'Test', videoPath: '');
    controller.infoAnimationController = AnimationController(vsync: tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(body: PlayerControls(controller: controller, videoState: VideoState())),
    ));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.pumpAndSettle();
      expect(Overlayment.count, 1);
      controller.requestFocusOnPlayer();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(Overlayment.count, 0);
    }

    final inputFocus = FocusNode();
    final input = TextEditingController();
    WidgetsBinding.instance.scheduleFrame();
    final panel = OverPanel(
      actions: OverlayActions(onReady: () async => inputFocus.requestFocus()),
      child: TextField(autofocus: true, focusNode: inputFocus, controller: input),
    );
    unawaited(Overlayment.show(panel, context: navigator.currentContext));
    await tester.pumpAndSettle();
    controller.requestFocusOnPlayer();
    controller.isPlaying.value = true;
    controller.isPlaying.value = false;
    await tester.pumpAndSettle();
    expect(inputFocus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'search');
    expect(input.text, 'search');
    unawaited(Overlayment.dismiss(panel));
    await tester.pumpAndSettle();
    inputFocus.dispose();
    input.dispose();

    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: TextField(autofocus: true)))));
    await tester.pumpAndSettle();
    final routeFocus = FocusManager.instance.primaryFocus;
    controller.requestFocusOnPlayer();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(routeFocus));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Fullscreen mounts another controls instance above the original route.
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: PlayerControls(controller: controller, videoState: VideoState())),
    )));
    await tester.pumpAndSettle();
    controller.requestFocusOnPlayer();
    await tester.pumpAndSettle();
    expect(ModalRoute.of(FocusManager.instance.primaryFocus!.context!)!.isCurrent, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    controller.requestFocusOnPlayer();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    controller.requestFocusOnPlayer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.infoAnimationController.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjustments overlay updates controls and restores player shortcuts on dismiss', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(AppSettingService()..pref = _Preferences());
    addTearDown(Get.reset);
    final native = _NativePlayer();
    final controller = PlayerController()..player = _Player(native);
    controller.currentVideo.value = Videos(videoCode: '', title: 'Test', videoPath: '');
    controller.infoAnimationController = AnimationController(vsync: tester);

    final showControls = ValueNotifier(true);
    addTearDown(showControls.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(
      valueListenable: showControls,
      builder: (context, visible, child) => visible ? PlayerControls(controller: controller, videoState: VideoState()) : const SizedBox.shrink(),
    ))));
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    final brightnessSlider = find.descendant(
      of: find.ancestor(of: find.text('Brightness'), matching: find.byType(Column)).first,
      matching: find.byType(Slider),
    );
    await tester.tap(find.text('Cinematic'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(brightnessSlider).value, double.parse(native.properties['brightness']!));
    await tester.drag(brightnessSlider, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(brightnessSlider).value.round(), int.parse(native.properties['brightness']!));
    await tester.tap(find.byTooltip('Save current as custom'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byTooltip('Rotate right 90°'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Rotate left 90°'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(native.commands, [
      ['cycle-values', 'video-rotate', '0', '90', '180', '270'],
      ['cycle-values', 'video-rotate', '0', '270', '180', '90'],
    ]);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(native.properties['video-rotate'], '0');
    native.failRotation = true;
    await tester.tap(find.byTooltip('Rotate right 90°'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Failed to rotate video'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 600));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    showControls.value = false;
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.infoAnimationController.dispose();
  });
}
