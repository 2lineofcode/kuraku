import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Shared assets load from the organized bundle folders', () async {
    for (final asset in [
      'assets/images/app_icon.png',
      'assets/audio/download_complete.mp3',
      'assets/python/r18_importer.py',
      'assets/python/chat_database_worker.py',
      'assets/python/sql_editor_worker.py',
      'assets/python/visual_search_worker.py',
      'assets/sql/r18_video_code_migration.sql',
      'assets/sql/r18_catalog_setup.sql',
    ]) {
      expect((await rootBundle.load(asset)).lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  test('Downloader runs from bundled assets without copying into the app folder', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-bundled-assets-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AppSettingService()..appPath = directory.path;
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    expect(service.bundledAssetsPath, Platform.isMacOS
        ? p.join(p.dirname(executableDirectory), 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets')
        : p.join(executableDirectory, 'data', 'flutter_assets', 'assets'));
    service.bundledAssetsPath = p.absolute('assets');
    final binary = p.join(service.bundledAssetsPath, 'bin', Platform.isWindows ? 'windows-x64/kuraku.exe' : Platform.isLinux ? 'linux-x64/kuraku' : 'macos-arm64/kuraku');
    final result = await Process.run(binary, ['--help'], workingDirectory: directory.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await directory.list().isEmpty, isTrue);
  });
}
