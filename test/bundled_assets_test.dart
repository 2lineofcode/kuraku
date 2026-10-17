import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Downloader runs from bundled assets without copying into the app folder', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-bundled-assets-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AppSettingService()..appPath = directory.path;
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    expect(service.bundledAssetsPath, Platform.isMacOS
        ? p.join(p.dirname(executableDirectory), 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets')
        : p.join(executableDirectory, 'data', 'flutter_assets', 'assets'));
    service.bundledAssetsPath = p.absolute('assets');
    final binary = p.join(service.bundledAssetsPath, Platform.isWindows ? 'windows-x64/kuraku.exe' : Platform.isLinux ? 'linux-x64/kuraku' : 'kuraku');
    final result = await Process.run(binary, ['--help'], workingDirectory: directory.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await directory.list().isEmpty, isTrue);
  });
}
