import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tools extends PageToolsController {
  @override
  Future<void> onRefresh() async {}
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final requests = <Completer<List<Map<String, Object?>>>>[];
  final filters = <String?>[];
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) {
    if (where == 'video_path = ? AND is_deleted = 0') {
      return Future.value([{'video_path': whereArgs!.single, 'is_favorite': 0}]);
    }
    expect(orderBy, 'filesize DESC');
    expect(limit, 200);
    filters.add(where);
    final request = Completer<List<Map<String, Object?>>>();
    requests.add(request);
    return request.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() { Get.testMode = true; });
  tearDown(() { Get.reset(); Get.clearTranslations(); });

  test('Large files ignore stale loads, expose errors and recover on retry', () async {
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    final controller = _Tools();
    final oldLoad = controller.getTopLargeFileSize(mode: 'internal');
    final newLoad = controller.getTopLargeFileSize(mode: 'external');
    expect(controller.topLargeLoading.value, isTrue);
    final external = Platform.isLinux
        ? "(video_path LIKE '/media/%' OR video_path LIKE '/mnt/%' OR video_path LIKE '/run/media/%')"
        : Platform.isWindows
        ? "(UPPER(SUBSTR(video_path, 1, 1)) BETWEEN 'F' AND 'Z' AND SUBSTR(video_path, 2, 2) = ':\\') OR SUBSTR(video_path, 1, 2) = '\\\\'"
        : "video_path LIKE '/Volumes/%'";
    expect(db.filters, ['is_deleted = 0 AND (filesize > 0 AND NOT ($external))', 'is_deleted = 0 AND (filesize > 0 AND ($external))']);
    db.requests[1].complete([{'video_code': 'NEW-001', 'filesize': 200}]);
    await newLoad;
    db.requests[0].complete([{'video_code': 'OLD-001', 'filesize': 100}]);
    await oldLoad;
    expect(controller.topLargeFileSizeList.single.videoCode, 'NEW-001');
    expect(controller.topLargeFilterMode.value, 'external');
    expect(controller.topLargeLoading.value, isFalse);
    final failed = controller.getTopLargeFileSize(mode: 'external');
    db.requests.last.completeError(StateError('Unavailable database'));
    await failed;
    expect(controller.topLargeError.value, isNotEmpty);
    expect(controller.topLargeLoading.value, isFalse);
    final retry = controller.getTopLargeFileSize(mode: 'external');
    db.requests.last.complete([]);
    await retry;
    expect(controller.topLargeError.value, isEmpty);
    expect(controller.topLargeFileSizeList, isEmpty);
    controller.onClose();
  });

  testWidgets('Large files adapt to themes, locales and narrow widths with usable empty filters', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), (_) => Completer<Object?>().future);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), null);
    });
    final controller = Get.put<PageToolsController>(_Tools());
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    final directory = Directory.systemTemp.createTempSync('kuraku-large-files-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Get.put(AppSettingService()..appPath = directory.path..pref = _Preferences());
    Directory('${directory.path}/vid_thumbnail').createSync();
    File('${directory.path}/vid_thumbnail/ABC-001-long-filename.jpg').writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII='));
    controller.topLargeFileSizeList.addAll([
      Videos(videoCode: 'ABC-001', videoPath: '/Volumes/Archive/long-folder/ABC-001-long-filename.mp4', quality: '3840x2160', filesize: 8000000000),
      Videos(filesize: null),
    ]);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    const output = String.fromEnvironment('LARGE_FILES_QA_PATH');
    if (font.isNotEmpty) await tester.runAsync(() async {
      await (FontLoader('VisualQA')..addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
    });
    final boundary = GlobalKey();
    for (final language in ['en', 'id']) {
      Get.locale = Locale(language);
      for (final dark in [false, true]) {
        final theme = AppStyle.theme(dark ? Brightness.dark : Brightness.light);
        for (final width in [800.0, 360.0]) {
          tester.view.physicalSize = Size(width, 600);
          await tester.pumpWidget(GetMaterialApp(translations: AppTranslations(), locale: Locale(language),
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: font.isEmpty ? null : 'VisualQA')),
            home: Builder(builder: (context) {
              AppColor.dependOn(context);
              return Scaffold(backgroundColor: AppColor.body, body: RepaintBoundary(key: boundary,
                child: Padding(padding: const EdgeInsets.all(16), child: const PageToolsView().uiTopLargeFileSize()),
              ));
            }),
          ));
          await tester.pumpAndSettle();
          expect(find.text('ABC-001', skipOffstage: false), findsOneWidget);
          expect(find.text('ABC-001-long-filename.mp4', skipOffstage: false), findsOneWidget);
          expect(find.text('4K', skipOffstage: false), findsOneWidget);
          final rowMenu = tester.widgetList<ExVideoContextMenu>(find.byType(ExVideoContextMenu, skipOffstage: false))
            .firstWhere((menu) => menu.child is Material);
          expect(rowMenu.videoPath, controller.topLargeFileSizeList.first.videoPath);
          expect(rowMenu.videoCode, 'ABC-001');
          expect(rowMenu.screenshotItems, same(controller.topLargeFileSizeList));
          expect(find.text('null', skipOffstage: false), findsNothing);
          final folders = tester.widgetList<IconButton>(find.byType(IconButton, skipOffstage: false)).where((button) => button.tooltip == 'Open File Path'.tr).toList();
          expect(folders.first.onPressed, isNotNull);
          expect(folders.last.onPressed, isNull);
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty && width == 800) await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output-$language-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    final menuWidget = tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget, skipOffstage: false).first);
    final menu = await menuWidget.menuProvider(scm.MenuRequest(
      onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero));
    notifier.dispose();
    expect(menu!.children.map((item) => item is scm.MenuSeparator ? '---' : item.title),
      ['Play'.tr, 'Add to Panel Cart'.tr, '---', 'Add To Favorite'.tr, 'Add to Playlist'.tr,
        '---', 'Edit Metadata'.tr, 'Refresh Metadata'.tr, 'Open File Path'.tr, 'Properties'.tr]);
    controller.topLargeFileSizeList.clear();
    await tester.pumpAndSettle();
    expect(find.text('No files with a recorded size in this location.'.tr), findsOneWidget);
    final dropdown = tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>));
    dropdown.onChanged!('external');
    await tester.pump();
    expect(controller.topLargeFilterMode.value, 'external');
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(AppDropdown<String>), findsOneWidget);
    db.requests.last.completeError(StateError('Unavailable database'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load videos. Please retry.'.tr), findsOneWidget);
    await tester.tap(find.text('Retry'.tr));
    await tester.pump();
    expect(db.filters.last, contains(Platform.isWindows ? "BETWEEN 'F' AND 'Z'" : Platform.isLinux ? "LIKE '/media/%'" : "LIKE '/Volumes/%'"));
    db.requests.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No files with a recorded size in this location.'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
