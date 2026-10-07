import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/player/player_controller.dart';
import 'package:javit/app/modules/player/player_mini_view.dart';
import 'package:javit/app/routes/app_pages.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  Future<void> write(String key, dynamic value) async => values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController implements VideoController {
  @override
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends PlayerController {
  final calls = <String>[];
  Duration? lastSeek;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> onClose() async {}

  @override
  Future<void> seekRelative(Duration offset) async {
    lastSeek = offset;
    calls.add('seek');
  }

  @override
  Future<void> nextVideo() async => calls.add('next');

  @override
  Future<void> prevVideo() async => calls.add('prev');

  @override
  Future<void> togglePlayPause() async => calls.add('toggle');

  @override
  Future<void> stopPlayback() async => calls.add('stop');

  @override
  void exitMiniMode() {
    calls.add('exitMini');
    super.exitMiniMode();
  }

  @override
  void requestFocusOnPlayer() {
    calls.add('focus');
    super.requestFocusOnPlayer();
  }
}

void main() {
  late _Controller controller;

  setUp(() {
    Get.put(AppSettingService()..pref = _Preferences());
    controller = _Controller();
    controller.videoController = _VideoController();
    controller.isPlayerVisible.value = true;
    controller.isMiniMode.value = true;
    controller.currentVideo.value = Videos(videoCode: 'ABP-001', title: 'A long title');
    Get.put<PlayerController>(controller);
  });
  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(body: Stack(children: [PlayerMiniView()])),
      getPages: [GetPage(name: Routes.PLAYER, page: () => const Scaffold(body: Text('Full player')))],
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('stays hidden unless the player is both visible and in mini mode', (tester) async {
    controller.isMiniMode.value = false;
    await pump(tester);
    expect(find.text('ABP-001'), findsNothing);

    controller.isMiniMode.value = true;
    await tester.pumpAndSettle();
    expect(find.text('ABP-001'), findsOneWidget);

    controller.isPlayerVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('ABP-001'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('prefers the video code and falls back to the title', (tester) async {
    await pump(tester);
    expect(find.text('ABP-001'), findsOneWidget);

    controller.currentVideo.value = Videos(videoCode: '', title: 'Only a title');
    await tester.pumpAndSettle();
    expect(find.text('Only a title'), findsOneWidget);

    controller.currentVideo.value = Videos();
    await tester.pumpAndSettle();
    expect(find.text(''), findsOneWidget);
  });

  testWidgets('shows the playback progress and a spinner until the texture is ready', (tester) async {
    controller.duration.value = const Duration(seconds: 100);
    controller.position.value = const Duration(seconds: 25);
    await pump(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'no texture id yet');
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(0.25, 1e-9));

    controller.position.value = const Duration(seconds: 500);
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 1.0, reason: 'clamped to the end');

    controller.duration.value = Duration.zero;
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.0);
  });

  testWidgets('play button mirrors the playback state', (tester) async {
    await pump(tester);
    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);

    controller.isPlaying.value = true;
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('transport buttons forward to the controller', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(controller.calls, ['prev', 'toggle', 'next', 'stop']);
  });

  testWidgets('tapping the preview leaves mini mode and opens the full player', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(controller.calls, contains('exitMini'));
    expect(controller.isMiniMode.value, isFalse);
    expect(find.text('Full player'), findsOneWidget);
    expect(Get.currentRoute, Routes.PLAYER);
  });

  testWidgets('arrow keys seek by the configured short step', (tester) async {
    await pump(tester);
    final step = AppPref.getPlayerSeekShort();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.lastSeek, Duration(seconds: step));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.lastSeek, Duration(seconds: -step));
    expect(controller.calls, ['seek', 'seek']);
  });

  testWidgets('the P shortcut restores the full player', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();

    expect(controller.isMiniMode.value, isFalse);
    expect(controller.calls, contains('exitMini'));
    expect(find.text('Full player'), findsOneWidget);
    expect(Get.currentRoute, Routes.PLAYER);
  });
}
