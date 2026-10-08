import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/local_video_selection.dart';
import 'package:javit/app/modules/home/local_video_selection_item.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_view.dart';
import 'package:javit/app/modules/home/page_home/page_home_controller.dart';
import 'package:javit/app/modules/home/page_home/page_home_view.dart';
import 'package:javit/app/modules/home/page_search/page_search_file_drag.dart';
import 'package:javit/app/modules/widgets/widget_double_tap.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import 'chat_test_database.dart';

mixin _Actions on LocalVideoSelection {
  final actions = <({String action, List<Videos> videos})>[];
  Map<String, String>? moved;
  @override
  Future<void> performSelectionAction(String action, List<Videos> selected) async { actions.add((action: action, videos: selected)); }
  @override
  Future<void> applyFileMoves(Map<String, Videos> files, Map<String, String> paths, List<String> missing) async {
    moved = paths;
    expect(missing, isEmpty);
  }
}

class _Home extends PageHomeController with _Actions {
  @override
  Future<void> onRefresh() async {}
}

class _Explore extends PageExploreTab with _Actions {
  _Explore(super.id);
  @override
  Future<(List<Videos>, int)> loadSelection(String menu, LeftListModel item) async => ([Videos(id: 'new')], 0);
}

void main() {
  setUp(() { Get.put(AppSettingService()..pref = ChatTestPreferences()); });
  tearDown(Get.reset);

  _Home home(List<Videos> videos) {
    AppPref.setBool(AppPref.homeSecNewRelease, true);
    AppPref.setBool(AppPref.homeSecFavorite, true);
    final controller = Get.put<PageHomeController>(_Home()) as _Home;
    controller.homeSectionOrder.assignAll([AppPref.homeSecNewRelease, AppPref.homeSecFavorite]);
    controller.listNewRelease.assignAll(videos);
    controller.listFavorite.add(Videos(id: videos.first.id, title: 'Duplicate'));
    return controller;
  }

  _Explore explore(List<Videos> videos) {
    final controller = _Explore(1);
    controller.currentMenuSelected.value = kPath;
    controller.rightListLocal.assignAll(videos);
    addTearDown(controller.dispose);
    return controller;
  }

  for (final surface in ['Home fan art', 'Home poster', 'Explore Local']) {
    testWidgets('$surface follows Search command selection, batch menu and Clear', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final videos = List.generate(3, (i) => Videos(id: '$i', title: 'Video $i', videoCode: ''));
      final LocalVideoSelection controller = surface.startsWith('Home') ? home(videos) : explore(videos);
      Widget card(Videos video) => switch (surface) {
        'Home fan art' => const PageHomeView().buildLayoutFanArt(video),
        'Home poster' => const PageHomeView().buildLayoutPoster(video),
        _ => PageExploreTabView(controller: controller as PageExploreTab).buildLayoutPoster(video, 135, 210),
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        LocalVideoSelectionClear(controller: controller),
        Row(children: videos.map(card).toList()),
      ]))));
      await tester.pumpAndSettle();
      Future<void> commandClick(int index) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        final gesture = await tester.startGesture(tester.getCenter(find.byType(DoubleTap).at(index)), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 200));
      }
      await commandClick(0);
      await commandClick(1);
      expect(controller.selectedVideos, {videos[0], videos[1]});
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true), findsNWidgets(2));
      expect(find.text('2 selected · Clear'), findsOneWidget);
      await commandClick(0);
      expect(controller.selectedVideos, {videos[1]});
      await commandClick(0);

      final notifier = ValueNotifier<scm.MenuResult?>(null);
      addTearDown(notifier.dispose);
      final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero);
      final batch = tester.widgetList<scm.ContextMenuWidget>(find.ancestor(
        of: find.byType(DoubleTap).first, matching: find.byType(scm.ContextMenuWidget),
      )).firstWhere((menu) => menu.contextMenuIsAllowed(Offset.zero));
      final menu = (await batch.menuProvider(request))!;
      expect(menu.children.whereType<scm.MenuAction>().map((item) => item.title), ['Play as Playlist', 'Play in Grid Player', 'Add to cart', 'Add to Playlist', 'Add to favorite']);
      expect(tester.widgetList<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget)).where((menu) => !menu.contextMenuIsAllowed(Offset.zero)).length, 3);
      controller.toggleSelection(videos[1]);
      for (final action in menu.children.whereType<scm.MenuAction>()) { action.callback(); }
      final actions = controller as _Actions;
      expect(actions.actions.map((item) => item.action), ['play', 'playMulti', 'cart', 'playlist', 'favorite']);
      expect(actions.actions.every((item) => item.videos.length == 2 && item.videos.first.id == '0' && item.videos.last.id == '1'), isTrue);
      final thirdBatch = tester.widgetList<scm.ContextMenuWidget>(find.ancestor(
        of: find.byType(DoubleTap).last, matching: find.byType(scm.ContextMenuWidget),
      )).firstWhere((menu) => menu.contextMenuIsAllowed(Offset.zero));
      await thirdBatch.menuProvider(request);
      expect(controller.selectedVideos, {videos.last});
      await tester.pump();
      await tester.tap(find.text('1 selected · Clear'));
      await tester.pump();
      expect(controller.selectedVideos, isEmpty);
      expect(find.text('1 selected · Clear'), findsNothing);
      if (controller is _Home) { controller.clearVideoSelection(); } else { await (controller as _Explore).onSectionR18Tap(); }
      menu.children.whereType<scm.MenuAction>().first.callback();
      expect(actions.actions.length, 5);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final page in ['Home', 'Explore']) {
    testWidgets('$page regular clicks clear selection before opening info or playing', (tester) async {
      final video = Videos(id: 'local');
      final LocalVideoSelection controller = page == 'Home' ? home([video]) : explore([video]);
      var info = 0;
      var plays = 0;
      await tester.pumpWidget(MaterialApp(home: Material(child: LocalVideoSelectionItem(
        controller: controller, video: video,
        onSingleTap: () { expect(controller.selectedVideos, isEmpty); info++; },
        onDoubleTap: () { expect(controller.selectedVideos, isEmpty); plays++; },
        child: const SizedBox(width: 100, height: 100),
      ))));
      controller.toggleSelection(video);
      await tester.tap(find.byType(DoubleTap));
      await tester.pump(kDoubleTapTimeout);
      expect([info, plays], [1, 0]);
      controller.toggleSelection(video);
      await tester.tap(find.byType(DoubleTap));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(DoubleTap));
      await tester.pump(kDoubleTapTimeout);
      expect([info, plays], [1, 1]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('Home deduplicates IDs, follows section order and excludes hidden sections', () {
    final first = Videos(id: 'first');
    final second = Videos(id: 'second');
    final controller = home([first, second]);
    controller.toggleSelection(first);
    controller.toggleSelection(second);
    expect(controller.selectedInOrder, [first, second]);
    expect(controller.isSelected(controller.listFavorite.single), isTrue);
    controller.toggleSelection(controller.listFavorite.single);
    expect(controller.selectedVideos, {second});
    controller.toggleSelection(first);
    controller.homeSectionOrder.assignAll([AppPref.homeSecFavorite, AppPref.homeSecNewRelease]);
    expect(controller.selectedInOrder.map((video) => video.id), ['first', 'second']);
    AppPref.setBool(AppPref.homeSecNewRelease, false);
    expect(controller.selectedInOrder.map((video) => video.id), ['first']);
    controller.clearVideoSelection();
    controller.toggleSelection(second);
    expect(controller.selectedVideos, isEmpty);
    controller.toggleSelection(controller.listFavorite.single);
    controller.listFavorite.clear();
    expect(controller.selectedVideos, isEmpty);
  });

  test('Explore selection is tab-local and clears on category, R18 and close', () async {
    final video = Videos(id: 'local');
    final controller = explore([video]);
    final other = _Explore(2)..rightListLocal.add(video);
    addTearDown(other.dispose);
    controller.toggleSelection(video);
    expect(other.selectedVideos, isEmpty);
    await controller.onLeftListTap(LeftListModel(name: '/new'));
    expect(controller.selectedVideos, isEmpty);
    controller.toggleSelection(controller.rightListLocal.single);
    final revision = controller.selectionRevision;
    await controller.onSectionR18Tap();
    expect(controller.selectedVideos, isEmpty);
    expect(controller.selectionRevision, greaterThan(revision));
    controller.toggleSelection(controller.rightListLocal.single);
    expect(controller.selectedVideos, isEmpty);
    await controller.onSectionLocalTap();
    controller.toggleSelection(controller.rightListLocal.single);
    controller.close();
    expect(controller.selectedVideos, isEmpty);
    controller.toggleSelection(controller.rightListLocal.single);
    expect(controller.selectedVideos, isEmpty);
  });

  for (final page in ['Home', 'Explore']) {
    for (final operation in ['move', 'copy', 'cancel']) {
      testWidgets('$page file drag exports the entire selection and handles $operation', (tester) async {
        final folder = Directory.systemTemp.createTempSync('javit-selection-');
        addTearDown(() => folder.deleteSync(recursive: true));
        final files = [File('${folder.path}/one.mp4')..writeAsStringSync('one'), File('${folder.path}/two.mp4')..writeAsStringSync('two')];
        final videos = List.generate(files.length, (i) => Videos(id: '$i', videoPath: files[i].path));
        final LocalVideoSelection controller = page == 'Home' ? home(videos) : explore(videos);
        controller.selectedVideos.addAll(videos);
        final drag = SearchFileDrag(controller: controller, video: videos.first, child: const SizedBox());
        final moves = <String, String>{};
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SearchFileDrag.channel, (call) async {
          if (call.method == 'bookmark') {
            expect(call.arguments, files.map((file) => file.path).toList());
            return {for (final file in files) file.path: [1]};
          }
          if (call.method == 'drag') {
            expect(call.arguments, files.map((file) => file.path).toList());
            controller.selectedVideos.clear();
            if (operation == 'move') {
              for (final file in files) {
                final target = '${file.path}.moved';
                file.renameSync(target);
                moves[file.path] = target;
              }
            }
            return operation;
          }
          expect(call.method, 'resolve');
          return moves;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SearchFileDrag.channel, null));
        await tester.runAsync(drag.startDrag);
        expect((controller as _Actions).moved, operation == 'move' ? moves : operation == 'copy' ? isEmpty : isNull);
        expect(drag.canDrag, isFalse);
      });
    }
  }
}
