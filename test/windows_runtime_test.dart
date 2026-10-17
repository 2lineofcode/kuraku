import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/core/app_notification.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_job.dart';
import 'package:kuraku/app/utils/helper_misc.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Notifications with MockPlatformInterfaceMixin implements FlutterLocalNotificationsWindows {
  int initializations = 0;
  String? receivedPayload;

  @override
  Future<bool> initialize({required WindowsInitializationSettings settings, DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse}) async {
    expect(settings.appName, 'KuraKu');
    expect(settings.appUserModelId, '2lineofcode.KuraKu');
    expect(settings.guid, '473d5457-5686-4e6e-a8ed-b2fabfb318c5');
    if (++initializations == 1) throw StateError('Notification service unavailable');
    return true;
  }

  @override
  Future<void> show({required int id, String? title, String? body, WindowsNotificationDetails? notificationDetails, String? payload}) async {
    expect(notificationDetails, isNotNull);
    receivedPayload = payload;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows notifications retry failed setup and forward download payloads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final previous = LinuxFlutterLocalNotificationsPlugin();
    addTearDown(() {
      FlutterLocalNotificationsPlatform.instance = previous;
      debugDefaultTargetPlatformOverride = null;
    });
    final plugin = _Notifications();
    FlutterLocalNotificationsPlatform.instance = plugin;
    await expectLater(AppNotification.initialize(), throwsStateError);
    await AppNotification.initialize();
    await AppNotification.show(const NotificationModel(title: 'Complete', body: 'Ready', payload: 'download'));
    expect(plugin.initializations, 2);
    expect(plugin.receivedPayload, 'download');
  });

  test('Windows disk capacity uses the native API and accepts Unicode paths', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku 日本語 ');
    addTearDown(() => directory.delete(recursive: true));
    final usage = HelperMisc.windowsStorageUsage(directory.path)!;
    expect(usage['total'], greaterThan(0));
    expect(usage['free'], inInclusiveRange(0, usage['total']!));
    expect(HelperMisc.windowsStorageUsage('${directory.path}\\missing'), isNull);
    expect(HelperMisc.isExternalDrive(r'F:\Movies'), isTrue);
    expect(HelperMisc.isExternalDrive(r'C:\Movies'), isFalse);
    expect(HelperMisc.isExternalDrive(r'\\server\share\Movies'), isTrue);
  }, skip: !Platform.isWindows);

  test('Windows downloads reject reserved device names before starting a process', () {
    for (final filename in ['CON', 'con.mp4', 'NUL.txt', 'COM1.mp4', 'LPT9.bin']) {
      expect(() => DownloadRequest(url: 'https://example.com/video', directory: Directory.systemTemp.path,
        filename: filename, mode: 'file').validate(), throwsFormatException);
    }
    DownloadRequest(url: 'https://example.com/video', directory: Directory.systemTemp.path,
      filename: '日本語 & file.mp4', mode: 'file').validate();
  }, skip: !Platform.isWindows);
}
