import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;

  setUp(() async => directory = await Directory.systemTemp.createTemp('kuraku-app-path-'));
  tearDown(() => directory.delete(recursive: true));

  test('uses the platform folder name for a fresh installation', () async {
    expect(await AppSettingService.prepareAppPath(directory.path),
      p.join(directory.path, Platform.isLinux ? '.KuraKu' : 'KuraKu'));
  });

  test('Linux migrates existing data intact and reuses the hidden folder', () async {
    final previous = await Directory(p.join(directory.path, 'KuraKu')).create();
    await File(p.join(previous.path, 'kuraku.db')).writeAsBytes([1, 2, 3]);
    final runtime = await Directory(p.join(previous.path, 'semantic_runtime')).create();
    await File(p.join(runtime.path, 'ready')).writeAsString('keep runtime');
    final path = await AppSettingService.prepareAppPath(directory.path);
    expect(path, p.join(directory.path, '.KuraKu'));
    expect(await previous.exists(), isFalse);
    expect(await File(p.join(path, 'kuraku.db')).readAsBytes(), [1, 2, 3]);
    expect(await File(p.join(path, 'semantic_runtime', 'ready')).readAsString(), 'keep runtime');
    expect(await AppSettingService.prepareAppPath(directory.path), path);
  }, skip: !Platform.isLinux);

  test('Linux preserves both folders when migration would overwrite existing data', () async {
    final previous = await Directory(p.join(directory.path, 'KuraKu')).create();
    final hidden = await Directory(p.join(directory.path, '.KuraKu')).create();
    await File(p.join(previous.path, 'kuraku.db')).writeAsString('previous');
    await File(p.join(hidden.path, 'kuraku.db')).writeAsString('hidden');
    await expectLater(AppSettingService.prepareAppPath(directory.path), throwsA(isA<FileSystemException>()));
    expect(await File(p.join(previous.path, 'kuraku.db')).readAsString(), 'previous');
    expect(await File(p.join(hidden.path, 'kuraku.db')).readAsString(), 'hidden');
  }, skip: !Platform.isLinux);
}
