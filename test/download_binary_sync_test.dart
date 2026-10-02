import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('binary sync skips unchanged assets and restores updated, missing or damaged files', () async {
    final directory = await Directory.systemTemp.createTemp('javit-binary-sync-');
    addTearDown(() => directory.delete(recursive: true));
    final asset = File('${directory.path}/bundled_binary');
    await asset.writeAsString('version1');
    await asset.setLastModified(DateTime(2026, 1, 1));
    final preferences = _Preferences();
    final service = AppSettingService()..appPath = directory.path..pref = preferences;
    final installed = File('${directory.path}/javit_dl');

    expect(await service.syncDownloadBinary(asset), isTrue);
    expect(await installed.readAsString(), 'version1');
    final installedStamp = (await installed.stat()).modified;
    final savedStamp = Map<String, dynamic>.from(preferences.values);
    expect(await service.syncDownloadBinary(asset), isFalse);
    expect((await installed.stat()).modified, installedStamp);
    expect(preferences.values, savedStamp);

    await asset.writeAsString('version2');
    await asset.setLastModified(DateTime(2026, 1, 2));
    expect(await service.syncDownloadBinary(asset), isTrue);
    expect(await installed.readAsString(), 'version2');
    expect(await service.syncDownloadBinary(asset), isFalse);

    await installed.delete();
    expect(await service.syncDownloadBinary(asset), isTrue);
    await installed.writeAsString('damaged');
    expect(await service.syncDownloadBinary(asset), isTrue);
    expect(await installed.readAsString(), 'version2');
    await installed.writeAsString('corrupt2');
    await installed.setLastModified(DateTime(2026, 1, 3));
    expect(await service.syncDownloadBinary(asset), isTrue);
    expect(await installed.readAsString(), 'version2');

    final beforeFailure = Map<String, dynamic>.from(preferences.values);
    await asset.writeAsString('');
    await expectLater(service.syncDownloadBinary(asset), throwsA(isA<FileSystemException>()));
    expect(await installed.readAsString(), 'version2');
    expect(preferences.values, beforeFailure);
    expect(await directory.list().where((entry) => entry.path.split('/').last.startsWith('.javit_dl-')).isEmpty, isTrue);
  });
}
