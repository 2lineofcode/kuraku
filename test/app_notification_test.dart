import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/core/app_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestPermissions') return true;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('platform plugin', () {
    test('initialisation happens once and is reused by later calls', () async {
      await AppNotification.initialize(onNotificationTap: (_) {});
      final initialisations = calls.where((call) => call.method == 'initialize').length;
      expect(initialisations, 1);

      await AppNotification.initialize();
      await AppNotification.initialize(onNotificationTap: (_) {});
      expect(calls.where((call) => call.method == 'initialize'), hasLength(initialisations));
    });

    test('permission requests are forwarded and default to granted', () async {
      expect(await AppNotification.requestPermissions(), isTrue);
      expect(calls.map((call) => call.method), contains('requestPermissions'));
      expect(calls.firstWhere((call) => call.method == 'requestPermissions').arguments, containsPair('alert', true));
    });

    test('showing a notification sends the title, body and payload with a random id', () async {
      AppNotification.registerNotificationTapHandler((payload) {});
      await AppNotification.show(const NotificationModel(title: 'Scan done', body: '42 new videos', payload: 'scan'));

      final show = calls.lastWhere((call) => call.method == 'show');
      final arguments = Map<String, dynamic>.from(show.arguments as Map);
      expect(arguments['title'], 'Scan done');
      expect(arguments['body'], '42 new videos');
      expect(arguments['payload'], 'scan');
      expect(arguments['id'], isA<int>());
      expect(arguments['id'] as int, inInclusiveRange(100000, 10000000));
    });

  }, skip: !Platform.isMacOS ? 'the notification plugin is only wired up for macOS' : null);
}
