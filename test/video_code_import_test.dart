import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_videos.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_library.dart';
import 'package:sqflite/sqflite.dart';

class _TestDBService extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database, Transaction {
  final queries = <List<Object?>>[];
  final updates = <Map<String, Object?>>[];
  List<Map<String, Object?>> rows = [];

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    queries.add([table, where, whereArgs]);
    return rows;
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(where, "id = ? AND (video_code IS NULL OR TRIM(video_code) = '')");
    updates.add({'id': whereArgs!.single, ...values});
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Database database;

  setUp(() {
    database = _Database();
    Get.put<DBService>(_TestDBService()..dbMain = database..dbR18 = database);
  });
  tearDown(Get.reset);

  test('library import keeps detected codes when R18 has no metadata', () async {
    for (final code in ['DVES-050', 'MMR-AZ090', 'MBDD-2177', 'NAAC-072', 'REBD-1062']) {
      final path = '/Volumes/ImportTest/$code.mp4';
      final video = await HomePanelLibrary.processVideo(path, '/Volumes/ImportTest');
      expect(video?.videoCode, code);
      expect(video?.toJson()['video_code'], code);
      expect(video?.videoPath, path);
    }
    final nonJav = await HomePanelLibrary.processVideo('/Volumes/ABP-001/holiday.mp4', '/Volumes/ABP-001');
    expect(nonJav?.videoCode ?? '', isEmpty);
  });

  test('manual recovery only updates missing codes in the selected library', () async {
    database.rows = [
      {'id': '1', 'video_path': '/Volumes/ImportTest/DVES-050.mp4'},
      {'id': '2', 'video_path': '/Volumes/ImportTest/MMR-AZ090.mp4'},
      {'id': '3', 'video_path': '/Volumes/ABP-001/holiday.mp4'},
    ];
    expect(await DBVideos.recoverMissingVideoCodes('/Volumes/ImportTest'), 2);
    expect(database.queries.single, ['videos', "root_path = ? AND is_deleted = 0 AND (video_code IS NULL OR TRIM(video_code) = '')", ['/Volumes/ImportTest']]);
    expect(database.updates, [
      {'id': '1', 'video_code': 'DVES-050'},
      {'id': '2', 'video_code': 'MMR-AZ090'},
    ]);
    expect(await DBVideos.recoverMissingVideoCodes(''), 0);
    expect(database.queries.length, 1);
  });
}
