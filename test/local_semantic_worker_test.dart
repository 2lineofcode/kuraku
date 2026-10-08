import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/utils/local_semantic_worker.dart';
import 'package:javit/app/utils/semantic_search_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  _Database(this.path);
  @override
  final String path;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DBService extends DBService {
  @override
  Future<void> onReady() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Worker handles concurrent requests, startup cancellation and recovery', () async {
    Get.testMode = true;
    final directory = await Directory.systemTemp.createTemp('javit-worker-test-');
    final runtime = '${directory.path}/semantic_runtime';
    final python = await Process.run('python3', ['-c', 'import sys; print(sys.executable)']);
    expect(python.exitCode, 0);
    final executableDirectory = Platform.isWindows ? 'Scripts' : 'bin';
    final executableName = Platform.isWindows ? 'python.exe' : 'python';
    await Directory('$runtime/venv/$executableDirectory').create(recursive: true);
    await Link('$runtime/venv/$executableDirectory/$executableName').create(python.stdout.toString().trim());
    await Directory('$runtime/onnx').create();
    const sizes = {'onnx/vision_model_int8.onnx': 88648877, 'onnx/text_model_int8.onnx': 64070791, 'tokenizer.json': 2224119, 'LICENSE': 1064};
    for (final entry in sizes.entries) {
      final file = await File('$runtime/${entry.key}').open(mode: FileMode.write);
      await file.truncate(entry.value);
      await file.close();
    }
    await File('$runtime/ready').writeAsString(LocalSemanticWorker.readyMarker);
    final dbPath = '${directory.path}/javit.db';
    final created = await Process.run('python3', ['-c',
      'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE videos(id TEXT, video_path TEXT, updated_at TEXT, is_deleted INTEGER NOT NULL DEFAULT 0)"); c.execute("CREATE TABLE video_embeddings(video_id TEXT, source_text TEXT, model TEXT, embedding BLOB)"); c.close()', dbPath,
    ]);
    expect(created.exitCode, 0);
    Get.put<AppSettingService>(AppSettingService()..appPath = directory.path..bundledAssetsPath = p.absolute('assets'));
    Get.put<DBService>(_DBService()..dbMain = _Database(dbPath));
    addTearDown(() async {
      LocalSemanticWorker.stop();
      Get.reset();
      await directory.delete(recursive: true);
    });
    expect(await LocalSemanticWorker.isReady(), isTrue);
    await File('$runtime/LICENSE').writeAsString('truncated');
    expect(await LocalSemanticWorker.isReady(), isFalse);
    final license = await File('$runtime/LICENSE').open(mode: FileMode.write);
    await license.truncate(1064);
    await license.close();
    expect(await File('$runtime/visual_search_worker.py').exists(), isFalse);
    final plans = await Future.wait([LocalSemanticWorker.request('plan'), LocalSemanticWorker.request('plan')]);
    expect(plans.map((plan) => plan['total']), [0, 0]);
    expect(await File('$runtime/visual_search_worker.py').exists(), isFalse);
    LocalSemanticWorker.stop();
    final cancelled = LocalSemanticWorker.request('plan');
    LocalSemanticWorker.stop();
    await expectLater(cancelled, throwsA(isA<SemanticSearchException>()));
    expect((await LocalSemanticWorker.request('plan'))['total'], 0);
    SemanticSearchService.beginPlayback();
    await expectLater(SemanticSearchService.search('forest'), throwsA(isA<SemanticSearchException>()));
    SemanticSearchService.endPlayback();
    expect((await LocalSemanticWorker.request('plan'))['total'], 0);
    final owner = Object();
    final stale = LocalSemanticWorker.request('plan', {}, owner);
    final staleCheck = expectLater(stale, throwsA(isA<SemanticSearchException>()));
    final latest = LocalSemanticWorker.request('plan', {}, owner);
    await staleCheck;
    expect((await latest)['total'], 0);
    final populated = await Process.run('python3', ['-c',
      'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.executemany("INSERT INTO videos(id,video_path,updated_at) VALUES(?,?,?)", [("video-"+str(i).zfill(60), "/missing/"+str(i)+".mp4", "") for i in range(1500)]); c.commit(); c.close()', dbPath,
    ]);
    expect(populated.exitCode, 0);
    final largePlan = await LocalSemanticWorker.request('plan');
    expect((largePlan['ids'] as List).length, 1500);

  });
}
