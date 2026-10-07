import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/utils/r18_updater.dart';
import 'package:path/path.dart' as p;

class _DatabaseService extends DBService {
  int? activatedVersion;
  bool failActivation = false;
  @override
  Future<void> activateR18Database(String path, int version) async {
    if (failActivation) throw StateError('Activation failed');
    expect(await File(path).exists(), isTrue);
    activatedVersion = version;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Local selection chooses the newest newer dump and ignores stale, empty and malformed files', () async {
    final folder = await Directory.systemTemp.createTemp('r18 local selection ');
    addTearDown(() => folder.delete(recursive: true));
    for (final name in ['r18dotdev_dump_2026-09-29.sql', 'r18dotdev_dump_2026-10-06.sql.gz', 'r18dotdev_dump_2026-02-30.sql', 'r18dotdev_dump_unknown.sql', 'unrelated_2099-10-06.sql']) {
      await File('${folder.path}/$name').writeAsString('dump');
    }
    await File('${folder.path}/r18dotdev_dump_2026-10-13.sql').create();
    await Directory('${folder.path}/r18dotdev_dump_2099-10-06.sql').create();
    final selected = await R18Updater.findLocalDump(folder.path, 20260922);
    expect(selected?.date, DateTime(2026, 10, 6));
    expect(selected?.file.path, '${folder.path}/r18dotdev_dump_2026-10-06.sql.gz');
    expect(await R18Updater.findLocalDump(folder.path, 20261006), isNull);
  });

  test('App imports local SQL and gzip, removes the source on success and preserves it on failure or cancellation', () async {
    final folder = await Directory.systemTemp.createTemp('r18 local import ');
    addTearDown(() async {
      Get.reset();
      R18Updater.status.value = '';
      R18Updater.progress.value = -1;
      await folder.delete(recursive: true);
    });
    Get.put<AppSettingService>(AppSettingService()..appPath = folder.path..bundledAssetsPath = p.absolute('assets'));
    final db = _DatabaseService();
    Get.put<DBService>(db);
    for (final extension in ['sql', 'sql.gz']) {
      final source = File('${folder.path}/r18dotdev_dump_2099-10-06.$extension');
      final setup = await Process.run('python3', ['-B', '-c', '''
import gzip, runpy, sys
from pathlib import Path
dump = runpy.run_path('test/r18_update_test.py')['dump']()
if sys.argv[1].endswith('.gz'):
    with gzip.open(sys.argv[1], 'wt') as stream:
        stream.write(dump)
else:
    Path(sys.argv[1]).write_text(dump)
''', source.path]);
      expect(setup.exitCode, 0);
      expect(await R18Updater.update(confirm: (_, _) async => false), isNull);
      expect(await source.exists(), isTrue);
      db.failActivation = true;
      await expectLater(R18Updater.update(), throwsStateError);
      expect(await source.exists(), isTrue);
      expect(await File('${folder.path}/r18_2099_10_06.db').exists(), isFalse);
      db.failActivation = false;
      final messages = <String>[];
      expect(await R18Updater.update(confirm: (version, local) async {
        expect(version, 20991006);
        expect(local, isTrue);
        return true;
      }, onStatus: messages.add), 20991006);
      expect(db.activatedVersion, 20991006);
      expect(messages.any((message) => message.startsWith('Downloading')), isFalse);
      expect(await source.exists(), isFalse);
      await File('${folder.path}/r18_2099_10_06.db').delete();
    }
    expect(await folder.list().any((entry) => entry.path.contains('.r18-update-')), isFalse);
    expect(R18Updater.busy.value, isFalse);
    for (final asset in ['r18_database_importer.py', 'r18_video_code_migration.sql']) {
      expect(await File('${folder.path}/$asset').exists(), isFalse);
    }
  });

  test('R18 discovery falls back on 404, stops at installed version and propagates errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    var status = 404;
    final subscription = server.listen((request) {
      requests.add(request.uri.path);
      request.response.statusCode = request.uri.path.contains('2026-09-29') ? 200 : status;
      request.response.close();
    });
    final dio = Dio()..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _RealHttpOverrides().createHttpClient(null));
    final url = 'http://${server.address.address}:${server.port}';
    try {
      final date = await R18Updater.findLatest(dio, url, 20260922, DateTime(2026, 10, 6, 23));
      expect(date, DateTime.utc(2026, 9, 29));
      expect(requests, ['/r18dotdev_dump_2026-10-06.sql.gz', '/r18dotdev_dump_2026-09-29.sql.gz']);
      requests.clear();
      expect(await R18Updater.findLatest(dio, url, 20260929, DateTime(2026, 10, 6)), isNull);
      expect(requests.length, 1);
      requests.clear();
      expect(await R18Updater.findLatest(dio, url, 20261006, DateTime(2026, 10, 6)), isNull);
      expect(requests, isEmpty);
      status = 500;
      await expectLater(R18Updater.findLatest(dio, url, 0, DateTime(2026, 10, 6)), throwsA(isA<DioException>()));
      status = 404;
      await expectLater(R18Updater.findLatest(dio, url, 0, DateTime(2026, 9, 22)), throwsStateError);
    } finally {
      dio.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
