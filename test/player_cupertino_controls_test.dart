import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:kuraku/app/modules/player/player_controls.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _FullscreenControlsState extends VideoState {
  @override
  bool isFullscreen() => true;
}

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends PlayerController {
  String? subtitle;
  int subtitlePicks = 0;
  int stops = 0;
  Future<void> Function()? fullscreenAction;

  @override
  Future<void> stopPlayback() async { stops++; }

  @override
  Future<void> toggleFullscreen(VideoState state) async { await fullscreenAction?.call(); }

  @override
  Future<void> togglePlayPause() async { isPlaying.toggle(); }

  @override
  Future<void> seek(Duration target) async { position.value = target; }

  @override
  Future<void> seekRelative(Duration offset) async { position.value += offset; }

  @override
  Future<void> setPlaybackRate(double value) async { playbackSpeed.value = value; }

  @override
  Future<void> setVolumeNormalized(double value) async { volume.value = value; }

  @override
  Future<void> mute() async { volume.value = 0; }

  @override
  Future<void> selectSubtitle(SubtitleTrack track) async { subtitle = track.id; }

  @override
  Future<void> pickSubtitle() async { subtitlePicks++; }
}

void main() {
  late _Controller controller;
  setUp(() {
    Get.put(AppSettingService()..pref = _Preferences());
    controller = _Controller();
    controller.currentVideo.value = Videos(videoCode: '', title: 'Waktu Yang Dinanti · UNGU', videoPath: '', viewCount: 6);
    controller.playlist.assignAll([controller.currentVideo.value]);
    controller.duration.value = const Duration(minutes: 4, seconds: 38);
    controller.position.value = const Duration(seconds: 37);
    controller.volume.value = .5;
  });
  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, {double width = 760, GlobalKey? boundary}) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RepaintBoundary(key: boundary, child: Stack(children: [
      const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF343E53), Color(0xFF17171D), Color(0xFF5A3655)],
      )))),
      PlayerControls(controller: controller, videoState: VideoState()),
    ])))));
    await tester.pumpAndSettle();
  }

  testWidgets('Cupertino player fits desktop and narrow windows with zero duration and long titles', (tester) async {
    addTearDown(tester.view.reset);
    controller.infoAnimationController = AnimationController(vsync: tester);
    addTearDown(controller.infoAnimationController.dispose);
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    const output = String.fromEnvironment('PLAYER_QA_PATH');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        await (FontLoader('CupertinoSystemText')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
        await (FontLoader('packages/${CupertinoIcons.iconFontPackage}/${CupertinoIcons.iconFont}')..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
      });
    }
    final boundary = GlobalKey();
    for (final width in [760.0, 480.0, 360.0]) {
      await pump(tester, width: width, boundary: boundary);
      expect(find.byType(CupertinoButton), findsWidgets);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Slider), findsNWidgets(2));
      final thumb = SliderTheme.of(tester.element(find.byType(Slider).first)).thumbShape!;
      expect(thumb.getPreferredSize(true, false), const Size(10, 10));
      expect(find.byType(BackdropFilter), findsNWidgets(3));
      expect(find.text('00:37'), findsOneWidget);
      expect(find.text('-04:01'), findsOneWidget);
      final play = tester.getCenter(find.byTooltip('Play (Space)'));
      expect(play.dx, closeTo(width / 2, .1));
      expect(tester.takeException(), isNull);
      controller.currentVideo.value = Videos(videoCode: '', title: 'Waktu Yang Dinanti · UNGU', videoPath: '/tmp/kuraku-preview-test-missing.mp4');
      await tester.pump();
      final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(Slider).first));
      await tester.pump(const Duration(milliseconds: 50));
      final preview = find.byType(CompositedTransformFollower);
      expect(preview, findsOneWidget);
      expect(find.ancestor(of: preview, matching: find.byType(ClipRRect)), findsNothing);
      if (output.isNotEmpty) await tester.runAsync(() async {
        final rendered = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File('$output-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }
    controller.duration.value = Duration.zero;
    controller.currentVideo.value = Videos(title: 'A long title ' * 30, videoPath: '');
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mini in [false, true]) {
    testWidgets('leaving fullscreen returns home with mini mode = $mini', (tester) async {
      controller.isPlayerVisible.value = true;
      controller.infoAnimationController = AnimationController(vsync: tester);
      addTearDown(controller.infoAnimationController.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(GetMaterialApp(navigatorKey: navigator, home: const Scaffold(body: Text('Home'))));
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
        body: PlayerControls(controller: controller, videoState: VideoState()),
      )));
      await tester.pumpAndSettle();
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
        body: PlayerControls(controller: controller, videoState: _FullscreenControlsState()),
      )));
      await tester.pumpAndSettle();
      controller.isFullScreen.value = true;
      controller.fullscreenAction = () async {
        expect(controller.stops, 0);
        navigator.currentState!.pop();
        controller.isFullScreen.value = false;
      };
      await tester.sendKeyEvent(mini ? LogicalKeyboardKey.keyP : LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(controller.stops, mini ? 0 : 1);
      expect(controller.isMiniMode.value, mini);
      expect(find.byType(PlayerControls), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('player tooltip survives resize and app reassembly', (tester) async {
    addTearDown(tester.view.reset);
    controller.infoAnimationController = AnimationController(vsync: tester);
    addTearDown(controller.infoAnimationController.dispose);
    await pump(tester);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byTooltip('Fullscreen')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    for (final width in [360.0, 1400.0, 760.0]) {
      tester.view.physicalSize = Size(width, 600);
      final reassembly = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reassembly;
      expect(tester.takeException(), isNull);
    }
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Video clicks toggle controls while mouse hover and playback actions still work', (tester) async {
    addTearDown(tester.view.reset);
    controller.infoAnimationController = AnimationController(vsync: tester);
    addTearDown(controller.infoAnimationController.dispose);
    await pump(tester);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(380, 250));
    await tester.pumpAndSettle();
    for (final visible in [false, true, false]) {
      await mouse.down(const Offset(380, 250));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play (Space)').hitTestable(), visible ? findsOneWidget : findsNothing);
      expect(controller.isPlaying.value, isFalse);
    }
    await mouse.moveTo(const Offset(390, 250));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play (Space)').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Play (Space)'));
    await tester.pumpAndSettle();
    expect(controller.isPlaying.value, isTrue);
    expect(find.byTooltip('Pause (Space)').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause (Space)').hitTestable(), findsNothing);
    await mouse.down(const Offset(390, 250));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause (Space)').hitTestable(), findsOneWidget);
    expect(controller.isPlaying.value, isTrue);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cmd Option C disables only playback controls until toggled again', (tester) async {
    addTearDown(tester.view.reset);
    controller.infoAnimationController = AnimationController(vsync: tester);
    addTearDown(controller.infoAnimationController.dispose);
    await pump(tester);
    Future<void> toggle() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Play (Space)').hitTestable(), findsOneWidget);
    final shortcuts = tester.widget<Shortcuts>(find.descendant(of: find.byType(PlayerControls), matching: find.byType(Shortcuts)).first);
    expect(shortcuts.shortcuts.containsKey(LogicalKeySet(LogicalKeyboardKey.equal)), isFalse);
    expect(find.byTooltip('Fullscreen').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(controller.isFullScreen.value, isFalse);
    await toggle();
    expect(controller.showPlaybackControls.value, isFalse);
    expect(find.byTooltip('Play (Space)').hitTestable(), findsNothing);
    expect(find.byTooltip('Subtitles').hitTestable(), findsOneWidget);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(380, 250));
    await mouse.moveTo(const Offset(390, 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(controller.position.value.inSeconds, greaterThan(37));
    expect(controller.isPlaying.value, isTrue);
    expect(find.byTooltip('Pause (Space)').hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    controller.currentVideo.value = Videos(title: 'Next video');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play (Space)').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
    expect(find.byTooltip('Play (Space)').hitTestable(), findsNothing, reason: 'new controls instances share the toggle');
    await toggle();
    expect(find.byTooltip('Play (Space)').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause (Space)').hitTestable(), findsNothing, reason: 'auto-hide remains enabled');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cupertino seeking and menus keep playback usable through auto-hide', (tester) async {
    addTearDown(tester.view.reset);
    controller.infoAnimationController = AnimationController(vsync: tester);
    addTearDown(controller.infoAnimationController.dispose);
    await pump(tester);
    final seek = find.byType(Slider).first;
    await tester.tapAt(tester.getTopLeft(seek) + Offset(tester.getSize(seek).width * .7, tester.getSize(seek).height / 2));
    await tester.pumpAndSettle();
    expect(controller.position.value.inSeconds, greaterThan(37));
    final clickedPosition = controller.position.value;
    final thumbDx = 22 + (tester.getSize(seek).width - 44) * clickedPosition.inMilliseconds / controller.duration.value.inMilliseconds;
    await tester.dragFrom(tester.getTopLeft(seek) + Offset(thumbDx, tester.getSize(seek).height / 2), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(controller.position.value, lessThan(clickedPosition));
    await tester.tap(find.byTooltip('Play (Space)'));
    await tester.pump();
    expect(controller.isPlaying.value, isTrue);
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('1.50×'), findsOneWidget);
    await tester.tap(find.text('1.50×'));
    await tester.pumpAndSettle();
    expect(controller.playbackSpeed.value, 1.5);
    expect(find.text('1.50×'), findsOneWidget, reason: 'the popover closes after selection');
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(controller.subtitle, 'no');
    expect(find.text('Load subtitle file…'), findsNothing);
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Load subtitle file…'), findsNothing);
    final playPosition = tester.getCenter(find.byTooltip('Pause (Space)'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(playPosition);
    await tester.pumpAndSettle();
    expect(controller.isPlaying.value, isTrue, reason: 'a hidden button only reveals the controls');
    await tester.tap(find.byTooltip('Pause (Space)'));
    await tester.pumpAndSettle();
    expect(controller.isPlaying.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
