import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:kuraku/app/routes/app_pages.dart';
import 'package:kuraku/app/utils/helper_loading.dart';
import 'package:kuraku/app/utils/helper_opener.dart';
import 'package:overlayment/overlayment.dart';

import 'chat_test_database.dart';

class _Controller extends PlayerController {
  final requests = <Completer<bool>>[];
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  Future<void> onClose() async {}
  @override
  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) {
    final request = Completer<bool>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  late _Controller controller;
  setUp(() {
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    controller = Get.put<PlayerController>(_Controller()) as _Controller;
  });
  tearDown(() { HelperLoading.dismiss(); Get.reset(); });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(body: Text('Library')),
      getPages: [GetPage(name: Routes.PLAYER, page: () => const Scaffold(body: Text('Player screen')))],
    ));
    await tester.pumpAndSettle();
  }

  Future<void> renderLoading(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opening player shows loading, ignores repeated opens and closes loading before navigation', (tester) async {
    await pump(tester);
    final opening = HelperOpener.openVideoFile(Videos(videoPath: '/video.mp4'));
    await renderLoading(tester);
    expect(find.text('Loading...'), findsOneWidget);
    expect(Overlayment.count, 1);
    await HelperOpener.openVideoFile(Videos(videoPath: '/another.mp4'));
    expect(controller.requests.length, 1);
    controller.requests.single.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Player screen'), findsOneWidget);
    expect(Overlayment.count, 0);
    Get.back();
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejected and failed playback dismiss loading and allow another open', (tester) async {
    await pump(tester);
    for (final throws in [false, true, false]) {
      final opening = HelperOpener.openVideoFile(Videos(videoPath: '/video.mp4'));
      final checked = throws ? expectLater(opening, throwsStateError) : opening;
      await renderLoading(tester);
      expect(find.text('Loading...'), findsOneWidget);
      if (throws) {
        controller.requests.last.completeError(StateError('Initialization failed'));
      } else {
        controller.requests.last.complete(false);
      }
      await checked;
      await tester.pumpAndSettle();
      expect(Overlayment.count, 0);
      expect(Get.currentRoute, isNot(Routes.PLAYER));
    }
    expect(controller.requests.length, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
