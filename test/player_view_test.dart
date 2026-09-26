import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/player/player_controller.dart';
import 'package:javit/app/modules/player/player_view.dart';
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
  int stops = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {}

  @override
  Future<void> stopPlayback() async => stops++;
}

void main() {
  late _Controller controller;

  setUp(() {
    Get.put(AppSettingService()..pref = _Preferences());
    controller = _Controller();
    controller.videoController = _VideoController();
    controller.currentVideo.value = Videos(videoCode: 'ABP-001', title: 'Test', videoPath: '/movies/ABP-001.mp4');
    Get.put<PlayerController>(controller);
  });
  tearDown(Get.reset);

  /// The desktop drag & drop plugin has no test implementation; its async
  /// registration error must not hide the assertions above it.
  void ignorePlatformChannelErrors(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  testWidgets('waits on the loading state before the video surface exists', (tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const PlayerView()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ValueListenableBuilder<int?>), findsNothing);

    controller.change(controller.currentVideo.value, status: RxStatus.success());
    await tester.pump();

    expect(find.byType(ValueListenableBuilder<int?>), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'no texture id yet');
    ignorePlatformChannelErrors(tester);
  });

  testWidgets('the drop hint is hidden and inert until a file hovers the window', (tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const PlayerView()));
    controller.change(controller.currentVideo.value, status: RxStatus.success());
    await tester.pump();

    AnimatedOpacity hint() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    IgnorePointer barrier() => tester.widget<IgnorePointer>(find.ancestor(of: find.byType(AnimatedOpacity), matching: find.byType(IgnorePointer)).first);

    expect(hint().opacity, 0);
    expect(barrier().ignoring, isTrue);
    expect(find.text('Drop video here'), findsOneWidget);

    controller.isDropHovering.value = true;
    await tester.pump();
    expect(hint().opacity, 1);
    expect(barrier().ignoring, isFalse);

    controller.isDropHovering.value = false;
    await tester.pump();
    expect(hint().opacity, 0);
    ignorePlatformChannelErrors(tester);
  });

  testWidgets('closing the route stops playback first', (tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Library'))));
    await tester.pumpAndSettle();

    unawaited(Get.to(() => const PlayerView()));
    await tester.pumpAndSettle();
    controller.change(controller.currentVideo.value, status: RxStatus.success());
    await tester.pump();
    expect(find.byType(PlayerView), findsOneWidget);

    unawaited(Get.key.currentState!.maybePop());
    await tester.pumpAndSettle();

    expect(controller.stops, 1);
    expect(find.text('Library'), findsOneWidget);
    ignorePlatformChannelErrors(tester);
  });

  testWidgets('in mini mode the route closes without touching the playback', (tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Library'))));
    await tester.pumpAndSettle();

    unawaited(Get.to(() => const PlayerView()));
    await tester.pumpAndSettle();
    controller.change(controller.currentVideo.value, status: RxStatus.success());
    controller.isMiniMode.value = true;
    await tester.pump();

    unawaited(Get.key.currentState!.maybePop());
    await tester.pumpAndSettle();

    expect(controller.stops, 0, reason: 'the mini player keeps playing');
    expect(find.text('Library'), findsOneWidget);
    ignorePlatformChannelErrors(tester);
  });
}
