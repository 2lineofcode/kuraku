import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PIN record survives disk reload and disabling preserves other preferences', () async {
    final directory = await Directory.systemTemp.createTemp('javit-pin-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() async {
      Get.reset();
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    final pref = GetSecureStorage(container: 'pin-test', password: 'test', path: directory.path);
    await pref.initStorage;
    Get.put<AppSettingService>(AppSettingService()..pref = pref);
    await pref.write('unrelated', 'keep');
    expect(await AppPref.setAppPin('1234'), isTrue);
    final stored = pref.read<Map>('_kAppPin');
    await File('${directory.path}/pin-test.gs').copy('${directory.path}/pin-restored.gs');
    final restored = GetSecureStorage(container: 'pin-restored', password: 'test', path: directory.path);
    await restored.initStorage;
    expect(restored.read<Map>('_kAppPin'), stored);
    expect(restored.read<String>('unrelated'), 'keep');
    expect(await AppPref.setAppPin(null, currentPin: '1234'), isTrue);
    await File('${directory.path}/pin-test.gs').copy('${directory.path}/pin-disabled.gs');
    final disabled = GetSecureStorage(container: 'pin-disabled', password: 'test', path: directory.path);
    await disabled.initStorage;
    expect(disabled.read('_kAppPin'), isNull);
    expect(disabled.read<String>('unrelated'), 'keep');
  });
}
