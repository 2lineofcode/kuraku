import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_shortcut.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/local_video_selection_item.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/modules/home/page_tools/tools_duplicate_comparison.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:kuraku/app/modules/widgets/widget_double_tap.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import 'chat_test_database.dart';

class _Tools extends PageToolsController {
  final actions = <List<Videos>>[];
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> checkIsHasDataNotScanned() async {}
  @override
  Future<void> performSelectionAction(String action, List<Videos> selected) async {
    expect(action, 'cart');
    actions.add(selected);
  }
}

class _Player extends PlayerController {
  final played = <Videos>[];
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  Future<void> onClose() async {}
  @override
  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) async {
    played.add(video);
    return false;
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'), (_) => Completer<Object?>().future);
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'), null);
  });

  for (final duplicate in [false, true]) {
    testWidgets('${duplicate ? 'Duplicate' : 'Large File'} supports range selection, batch cart, keyboard and restored scroll', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = Get.put<PageToolsController>(_Tools()) as _Tools;
      controller.currentMenuSelected.value = duplicate ? kDuplicate : kTopLargeFile;
      final videos = List.generate(30, (i) => Videos(id: '$i', videoPath: '/video-$i.mp4', videoCode: 'TEST-$i', filesize: 100));
      if (duplicate) {
        for (var i = 0; i < videos.length; i += 3) { controller.duplicateGroups.add(videos.sublist(i, i + 3)); }
      } else {
        controller.topLargeFileSizeList.assignAll(videos);
      }
      final visible = true.obs;
      await tester.pumpWidget(GetMaterialApp(home: Builder(builder: (context) {
        AppColor.dependOn(context);
        return Scaffold(body: Obx(() => visible.value
          ? duplicate ? const PageToolsView().uiDuplicateVideo() : const PageToolsView().uiTopLargeFileSize()
          : const SizedBox.shrink()));
      })));
      await tester.pumpAndSettle();
      Finder row(int index) => find.byWidgetPredicate((widget) => widget is LocalVideoSelectionItem && widget.video == videos[index], skipOffstage: false);
      Future<void> click(int index, LogicalKeyboardKey modifier) async {
        await tester.sendKeyDownEvent(modifier);
        final target = find.descendant(of: row(index), matching: find.byType(DoubleTap, skipOffstage: false));
        await tester.tap(target);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
      }
      await click(0, AppShortcut.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
      await click(2, LogicalKeyboardKey.shiftLeft);
      expect(controller.selectedInOrder, videos.take(3));
      expect(find.text('3 selected · Clear'), findsOneWidget);
      final menuWidget = tester.widgetList<scm.ContextMenuWidget>(find.descendant(of: row(0), matching: find.byType(scm.ContextMenuWidget, skipOffstage: false)))
          .where((menu) => menu.contextMenuIsAllowed(Offset.zero)).first;
      final notifier = ValueNotifier<scm.MenuResult?>(null);
      final menu = await menuWidget.menuProvider(scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero));
      final cart = menu!.children.whereType<scm.MenuAction>().firstWhere((item) => item.title == 'Add to cart');
      cart.callback();
      await tester.pump();
      expect(controller.actions.single, videos.take(3));
      notifier.dispose();
      final focus = duplicate ? controller.duplicatesFocus : controller.largeFilesFocus;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(controller.activeVideoPath.value, videos[3].videoPath);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.selectedInOrder, videos.sublist(3, 5));
      final player = Get.put<PlayerController>(_Player()) as _Player;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(player.played, [videos[4]]);
      await tester.tap(find.descendant(of: row(4), matching: find.byType(DoubleTap, skipOffstage: false)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.descendant(of: row(4), matching: find.byType(DoubleTap, skipOffstage: false)));
      await tester.pumpAndSettle();
      expect(player.played, [videos[4], videos[4]]);
      expect(controller.selectedVideos, isEmpty);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.selectedVideos, isEmpty);
      expect(controller.actions, hasLength(1));
      cart.callback();
      await tester.pump();
      expect(controller.actions, hasLength(1), reason: 'Old menus must not act after selection is cleared');
      for (var i = 0; i < 23; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(controller.activeVideoPath.value, videos[22].videoPath);
      expect(row(22).hitTestable(), findsOneWidget);
      final scroll = duplicate ? controller.duplicatesScroll : controller.largeFilesScroll;
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Comparison probes sequentially, keeps missing-file metadata and renders narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final first = Completer<MediaInformation?>();
    final paths = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ToolsDuplicateComparison(
      videos: [Videos(videoPath: '/first.mp4'), Videos(videoPath: '/offline.mp4', quality: '1280x720', filesize: 1024)],
      onClose: () {},
      readFile: (path) {
        paths.add(path);
        if (paths.length == 1) return first.future;
        return Future.error(const FileSystemException('Offline'));
      },
    ))));
    await tester.pump();
    expect(paths, ['/first.mp4']);
    first.complete(MediaInformation({
      'format': {'size': '2048', 'duration': '120', 'bit_rate': '8000000'},
      'streams': [{'codec_type': 'video', 'codec_name': 'hevc', 'width': 1920, 'height': 1080}],
    }));
    await tester.pumpAndSettle();
    expect(paths, ['/first.mp4', '/offline.mp4']);
    expect(find.text('H.265'), findsOneWidget);
    expect(find.text('8000 kb/s'), findsOneWidget);
    expect(find.text('1280x720'), findsOneWidget);
    expect(find.text('0:02:00'), findsOneWidget);
    expect(find.textContaining('Could not read video properties.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
