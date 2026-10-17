import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_notification.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_shortcut.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_r18.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_tab.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Notifications extends LinuxFlutterLocalNotificationsPlugin {
  int initializations = 0;
  String? receivedPayload;

  @override
  Future<bool?> initialize({required LinuxInitializationSettings settings, DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse}) async {
    expect(settings.defaultActionName, 'Open');
    if (++initializations == 1) throw StateError('Notification service unavailable');
    return true;
  }

  @override
  Future<void> show({required int id, String? title, String? body, LinuxNotificationDetails? notificationDetails, String? payload}) async {
    expect(notificationDetails, isNotNull);
    receivedPayload = payload;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux notifications retry a failed setup and forward payloads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final previous = LinuxFlutterLocalNotificationsPlugin();
    final plugin = _Notifications();
    FlutterLocalNotificationsPlatform.instance = plugin;
    addTearDown(() => FlutterLocalNotificationsPlatform.instance = previous);
    await expectLater(AppNotification.initialize(), throwsStateError);
    await AppNotification.initialize();
    await AppNotification.show(const NotificationModel(title: 'Complete', body: 'Ready', payload: 'download'));
    expect(plugin.initializations, 2);
    expect(plugin.receivedPayload, 'download');
  }, skip: !Platform.isLinux);

  test('FFI desktop startup creates both databases, migrates R18 and persists library data', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-linux-db-');
    addTearDown(() async { Get.reset(); await directory.delete(recursive: true); });
    Get.put(AppSettingService()..appPath = directory.path);
    sqfliteFfiInit();
    final catalog = await databaseFactoryFfi.openDatabase('${directory.path}/r18_20261017.db');
    try {
      for (final statement in (await File('test/fixtures/r18_catalog.sql').readAsString()).split(';')) {
        if (statement.trim().isNotEmpty) await catalog.execute(statement);
      }
    } finally {
      await catalog.close();
    }
    var service = await DBService().init();
    Get.put<DBService>(service);
    try {
      final home = PageHomeController();
      await home.getListNewRelease();
      await home.getListOldest();
      final explore = PageExploreTab(1, pins: <String>{}.obs);
      try {
        expect(await explore.getCustomList(), isNotEmpty);
        expect(await DBR18.getAllActress(), isNotEmpty);
      } finally {
        explore.dispose();
      }
      expect(await service.dbMain.getVersion(), DBUpdate.version);
      expect(await service.dbMain.rawQuery('PRAGMA foreign_keys'), [containsPair('foreign_keys', 1)]);
      expect(await service.dbR18!.rawQuery('SELECT video_code FROM derived_video LIMIT 1'), isNotEmpty);
      await service.dbMain.insert('library', {'id': 'linux', 'root_folder': '/mnt/日本語 videos', 'videos': '[]'});
    } finally {
      await service.close();
    }
    service = await DBService().init();
    try {
      expect((await service.dbMain.query('library')).single['root_folder'], '/mnt/日本語 videos');
      expect(await service.dbR18!.rawQuery("SELECT 1 FROM sqlite_master WHERE name = 'kuraku_catalog_groups_v2'"), isNotEmpty);
    } finally {
      await service.close();
    }
  }, skip: !Platform.isLinux && !Platform.isWindows);

  testWidgets('Desktop Ctrl shortcuts require the specified modifiers', (tester) async {
    const shortcut = AppShortcut(LogicalKeyboardKey.keyN);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(shortcut.accepts(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyN,
      logicalKey: LogicalKeyboardKey.keyN, timeStamp: Duration.zero), HardwareKeyboard.instance), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(shortcut.accepts(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyN,
      logicalKey: LogicalKeyboardKey.keyN, timeStamp: Duration.zero), HardwareKeyboard.instance), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(AppShortcut.label('⌘ + N'), 'Ctrl + N');
  }, skip: !Platform.isLinux && !Platform.isWindows);
}
