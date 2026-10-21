import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  List<Map<String, Object?>> rows = [];
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async => rows;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tools extends PageToolsController {
  final requests = <Completer<List<List<Videos>>>>[];
  @override
  // Avoid startup database queries in this isolated controller test.
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  Future<void> getTopLargeFileSize({String mode = 'all'}) async {}
  @override
  Future<void> checkIsHasDataNotScanned() async {}
  @override
  Future<List<List<Videos>>> loadDuplicateGroups(String mode) {
    final request = Completer<List<List<Videos>>>();
    requests.add(request);
    return request.future;
  }
  @override
  Future<Map<String, bool>> checkDuplicateFiles(List<List<Videos>> groups) async => {
    for (final video in groups.expand((group) => group)) video.videoPath!: !video.videoPath!.startsWith('/Volumes/'),
  };
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
}

void main() {
  tearDown(() { Get.reset(); Get.clearTranslations(); });

  test('resource refresh preserves Tools drafts and skips duplicate work outside its tab', () async {
    Get.put<DBService>(_Service()..dbMain = _Database());
    final tools = Get.put<PageToolsController>(_Tools()) as _Tools;
    tools.tecDuplicateSearch.text = 'Keep draft';
    tools.resultQuery.value = 'Keep search';
    tools.topLargeFilterMode.value = 'external';
    await tools.refreshVideoContent();
    expect(tools.requests, isEmpty);
    expect(tools.tecDuplicateSearch.text, 'Keep draft');
    expect(tools.resultQuery.value, 'Keep search');
    expect(tools.topLargeFilterMode.value, 'external');
    tools.currentMenuSelected.value = kDuplicate;
    final refresh = tools.refreshVideoContent();
    await Future<void>.delayed(Duration.zero);
    expect(tools.requests, hasLength(1));
    tools.requests.single.complete([]);
    await refresh;
    expect(tools.tecDuplicateSearch.text, 'Keep draft');
  });

  test('Duplicate matching handles quality suffixes, titles, Unicode and disconnected candidates', () async {
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    Map<String, Object?> row(String path, {String code = '', String title = '', int size = 100, int duration = 120}) => {
      'video_path': path, 'video_code': code, 'title': title, 'filesize': size, 'duration': duration,
    };
    Future<List<List<Videos>>> groups(List<Map<String, Object?>> rows, {String mode = 'probable'}) {
      database.rows = rows;
      return DBVideos.getDuplicateVideoGroups(mode: mode);
    }
    expect(await groups([row('/a.mp4', code: 'ABC-001'), row('/b.mp4', code: 'abc-001', size: 300)], mode: 'exact'), hasLength(1));
    expect(await groups([row('/film_1080p.mp4'), row('/film_720p.mp4')], mode: 'exact'), hasLength(1));
    expect(await groups([row('/first.mp4', title: 'Shared title'), row('/second.mp4', title: 'Shared title', duration: 122)]), hasLength(1));
    expect(await groups([row('/日本の映画_1080p.mp4'), row('/日本の映画_720p.mp4')]), hasLength(1));
    expect(await groups([row('/film_1080p.mp4', duration: 30), row('/film_720p.mp4', duration: 180)]), isEmpty);
    final separated = await groups([for (final duration in [10, 11, 300, 301]) row('/$duration/film.mp4', duration: duration)]);
    expect(separated.map((group) => group.length), [2, 2]);
    final overlapping = await groups([row('/film_1080p.mp4', title: 'Shared title'), row('/film_720p.mp4', title: 'Shared title')]);
    expect(overlapping.single, hasLength(2));
    expect(await groups([row('/film_1080p.mp4', code: 'ABC-001'), row('/film_720p.mp4', code: 'ABC-002')]), isEmpty);
    expect(await groups([row('/film [part 1].mp4'), row('/film [part 2].mp4')]), isEmpty);
    expect(await groups([row('/film.mp4', size: 0), row('/copy/film.mp4', size: 0)], mode: 'exact'), isEmpty);
    expect(await groups([row('/film.mp4', size: 100, duration: 0), row('/copy/film.mp4', size: 60, duration: 0)]), hasLength(1));
  });

  test('Duplicate refresh rejects stale scans, keeps mode, and recovers from errors', () async {
    final controller = _Tools();
    final group = [Videos(videoPath: '/one.mp4'), Videos(videoPath: '/two.mp4')];
    final old = controller.getDuplicateVideos();
    final current = controller.setDuplicateMode('probable');
    controller.requests.first.complete([group]);
    await old;
    expect(controller.duplicateGroups, isEmpty);
    expect(controller.duplicateLoading.value, isTrue);
    controller.requests.last.complete([group]);
    await current;
    expect(controller.duplicateVideoCount, 2);
    controller.currentMenuSelected.value = kDuplicate;
    final refresh = controller.onRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.duplicateMode.value, 'probable');
    expect(controller.duplicateGroups, isEmpty);
    controller.requests.last.complete([group]);
    await refresh;
    expect(controller.duplicateVideoCount, 2);
    final failure = controller.getDuplicateVideos();
    controller.requests.last.completeError(StateError('Unavailable database'));
    await failure;
    expect(controller.duplicateError.value, isNotEmpty);
    expect(controller.duplicateLoading.value, isFalse);
    final retry = controller.getDuplicateVideos();
    controller.requests.last.complete([group]);
    await retry;
    expect(controller.duplicateError.value, isEmpty);
    expect(controller.duplicateVideoCount, 2);
    final leaving = controller.getDuplicateVideos();
    await controller.onReset();
    controller.requests.last.complete([group]);
    await leaving;
    expect(controller.duplicateGroups, isEmpty);
    controller.onClose();
  });

  testWidgets('Duplicate groups fit compact widths and search keeps comparison files together', (tester) async {
    Get.testMode = true;
    final home = Get.put<HomeController>(_Home());
    final controller = Get.put<PageToolsController>(_Tools());
    controller.duplicateGroups.add([
      Videos(videoCode: 'ABC-001', videoPath: '/Users/adit/Videos/ABC-001_1080p.mp4', quality: '1920x1080', filesize: 3200000000, duration: 120),
      Videos(videoCode: 'ABC-001', videoPath: '/Volumes/Archive/ABC-001_720p.mp4', quality: '1280x720', filesize: 1600000000, duration: 122),
    ]);
    controller.duplicateFileAvailable['/Users/adit/Videos/ABC-001_1080p.mp4'] = true;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    const output = String.fromEnvironment('DUPLICATE_QA_PATH');
    if (font.isNotEmpty) await tester.runAsync(() async {
      await (FontLoader('VisualQA')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    final boundary = GlobalKey();
    for (final language in ['en', 'id']) {
      for (final dark in [false, true]) {
        for (final width in [665.0, 550.0, 360.0]) {
          Get.locale = Locale(language);
          tester.view.physicalSize = Size(width, 620);
          await tester.pumpWidget(GetMaterialApp(translations: AppTranslations(), locale: Locale(language),
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, fontFamily: font.isEmpty ? null : 'VisualQA'),
            home: Builder(builder: (context) {
              AppColor.dependOn(context);
              return Scaffold(body: RepaintBoundary(key: boundary, child: ColoredBox(color: AppColor.body,
                child: CupertinoTheme(data: CupertinoThemeData(brightness: dark ? Brightness.dark : Brightness.light,
                  primaryColor: AppColor.text, textTheme: CupertinoTextThemeData(
                  textStyle: TextStyle(fontFamily: font.isEmpty ? null : 'VisualQA'),
                )), child: Padding(padding: const EdgeInsets.all(16), child: const PageToolsView().uiDuplicateVideo())),
              )));
            }),
          ));
          await tester.pumpAndSettle();
          expect(find.text('ABC-001_1080p.mp4'), findsOneWidget);
          expect(find.text('ABC-001_720p.mp4'), findsOneWidget);
          final menus = tester.widgetList<ExVideoContextMenu>(find.byType(ExVideoContextMenu)).toList();
          expect(menus.map((menu) => menu.videoPath), controller.duplicateGroups.single.map((video) => video.videoPath));
          for (final filename in ['ABC-001_1080p.mp4', 'ABC-001_720p.mp4']) {
            final row = find.ancestor(of: find.text(filename), matching: find.byType(InkWell));
            expect(tester.widget<InkWell>(row).onTap, isNotNull);
          }
          expect(find.text(language == 'id' ? 'Video Sama' : 'Same Video'), findsOneWidget);
          final folders = tester.widgetList<IconButton>(find.byType(IconButton)).where((button) => button.tooltip == 'Open File Path'.tr).toList();
          expect(folders.first.onPressed, isNotNull);
          expect(folders.last.onPressed, isNull);
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty && width == 550) await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output-$language-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    final database = _Database()..rows = [controller.duplicateGroups.single.first.toJson()];
    Get.put<DBService>(_Service()..dbMain = database);
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    final menuWidget = tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget).first);
    final menu = await menuWidget.menuProvider(scm.MenuRequest(
      onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero));
    notifier.dispose();
    expect(menu!.children.map((item) => item is scm.MenuSeparator ? '---' : item.title),
      ['Play'.tr, 'Add to Panel Cart'.tr, '---', 'Add To Favorite'.tr, 'Add to Playlist'.tr,
        '---', 'Edit Metadata'.tr, 'Refresh Metadata'.tr, 'Open File Path'.tr]);
    controller.duplicateQuery.value = '1080';
    await tester.pumpAndSettle();
    expect(find.text('ABC-001_720p.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to Panel Cart'.tr).first);
    await tester.pumpAndSettle();
    expect(home.cart, hasLength(1));
    expect(find.byTooltip('Already in panel cart'.tr), findsOneWidget);
    controller.duplicateQuery.value = 'missing';
    await tester.pumpAndSettle();
    expect(find.text('No matching groups'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
