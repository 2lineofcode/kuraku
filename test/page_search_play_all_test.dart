import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_log.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_view.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/utils/helper_opener.dart';
import 'package:toastification/toastification.dart';

import 'chat_test_database.dart';

class _Player extends PlayerController {
  final requests = <({Videos video, List<Videos>? playlist})>[];

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> onClose() async {}

  @override
  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) async {
    requests.add((video: video, playlist: playlist));
    return false;
  }
}

class _ExploreView extends PageExploreTabView {
  const _ExploreView({required super.controller});

  @override
  Widget buildLayoutPoster(Videos video, double width, double height, {
    showReleaseDate = true, showViewCount = true, showQuality = true,
  }) => Text(video.id ?? 'Video');
}

void main() {
  testWidgets('playlist playback filters missing files, preserves selection and warns for empty Search results', (tester) async {
    final directory = Directory.systemTemp.createTempSync('kuraku-search-play-');
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final player = Get.put<PlayerController>(_Player()) as _Player;
    final tab = PageSearchTab(1);
    addTearDown(() {
      toastification.dismissAll(delayForAnimation: false);
      HomePanelAppLog.clear();
      tab.dispose();
      Get.reset();
      directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(home: const Scaffold())));
    final missing = Videos(id: 'missing', videoPath: '${directory.path}/missing.mp4');
    final first = Videos(id: 'first', videoPath: (File('${directory.path}/first.mp4')..writeAsStringSync('fixture')).path);
    final second = Videos(id: 'second', videoPath: (File('${directory.path}/second.mp4')..writeAsStringSync('fixture')).path);
    tab.videos.assignAll([missing, Videos(), first, Videos(videoPath: ' '), second]);

    await tab.performSelectionAction('play', tab.videos.toList());
    expect(player.requests.single.video, same(first));
    expect(player.requests.single.playlist, [first, second]);
    expect(tab.videos.length, 5);

    await tab.performSelectionAction('play', [second, missing, first]);
    expect(player.requests.last.video, same(second));
    expect(player.requests.last.playlist, [second, first]);

    await tab.performSelectionAction('play', [missing, Videos(), Videos(videoPath: ' ')]);
    await tester.pumpAndSettle();
    expect(player.requests.length, 2);
    expect(HomePanelAppLog.appLogRuntime.first.type, 'WARN');
    expect(HomePanelAppLog.appLogRuntime.first.content, 'No playable video found. Check your external drive connection.');
    await tab.performSelectionAction('play', []);
    expect(player.requests.length, 2);

    await HelperOpener.openVideoFile(second, playlist: tab.videos);
    expect(player.requests.last.video, same(second));
    expect(player.requests.last.playlist, [first, second]);
    expect(tab.videos.length, 5);

    File(first.videoPath!).deleteSync();
    await HelperOpener.openVideoFile(second, playlist: tab.videos);
    expect(player.requests.last.playlist, [second]);

    await HelperOpener.openVideoFile(second);
    expect(player.requests.last.playlist, isNull);

    final explore = PageExploreTab(2);
    addTearDown(explore.dispose);
    addTearDown(tester.view.reset);
    explore.isFresh.value = false;
    explore.currentMenuSelected.value = kSeries;
    explore.leftListSelected.value = LeftListModel(name: 'Meguri (megu Fujiura) with a very long section name', count: 5);
    explore.rightListR18TotalVideo.value = 313;
    explore.rightListLocal.assignAll(tab.videos);
    final playAll = find.byKey(const ValueKey('explore-play-all'));
    for (final width in [800.0, 600.0]) {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(home: Scaffold(body: _ExploreView(controller: explore)))));
      await tester.pumpAndSettle();
      expect(playAll, findsOneWidget);
      await tester.tap(playAll);
      await tester.pumpAndSettle();
      expect(player.requests.last.video, same(second));
      expect(player.requests.last.playlist, [second]);
      expect(tester.takeException(), isNull);
    }
    explore.isLoadingSelection.value = true;
    await tester.pump();
    expect(tester.widget<AppButton>(playAll).onPressed, isNull);
    explore.isLoadingSelection.value = false;
    explore.rightListViewMode.value = kR18;
    await tester.pumpAndSettle();
    expect(playAll, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
