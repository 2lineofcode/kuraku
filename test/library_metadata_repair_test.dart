import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_library.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _MainDatabase implements Database {
  final row = <String, Object?>{
    'id': 'local-id', 'root_path': '/offline', 'video_path': '/offline/NAAC-066.mp4',
    'video_code': '', 'title': 'Old title', 'description': 'Custom description',
    'poster': 'Old poster', 'duration': 90, 'duration_formated': '1 hour, 30 minutes',
    'release_date': '2025-01-01', 'release_date_formated': 'Jan 01, 2025',
    'is_favorite': 1, 'view_count': 42, 'filesize': 12345, 'quality': '1920x1080',
    'created_at': '2025-01-01', 'actress': null, 'category': null, 'screenshot': null,
  };
  final updates = <Map<String, Object?>>[];

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'videos');
    expect(where, 'id = ? AND video_path = ? AND is_deleted = 0');
    if (whereArgs![0] != row['id'] || whereArgs[1] != row['video_path']) return 0;
    updates.add(Map.of(values));
    row.addAll(values);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _R18Database implements Database {
  bool emptyMetadata = false;
  bool fail = false;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (fail) throw StateError('R18 query failed');
    if (arguments!.single != 'NAAC-066') return [];
    if (sql.contains('LEFT JOIN machine_translation')) {
      return [{
        'id': 'r18-content-id', 'video_code': 'NAAC-066', 'title': 'New title',
        'title_ja': 'Japanese title', 'release_date': emptyMetadata ? null : '2026-09-29',
        'duration': emptyMetadata ? 0 : 120, 'poster': emptyMetadata ? null : 'New poster',
        'ssfirst': 'digital/video/naac00066/naac00066jp-1',
        'sslast': 'digital/video/naac00066/naac00066jp-3',
      }];
    }
    if (emptyMetadata) return [];
    if (sql.contains('derived_category')) return [{'id': 1, 'category': 'Drama'}];
    if (sql.contains('derived_actress')) return [{'id': 2, 'name_romaji': 'jane doe'}];
    if (sql.contains('derived_director')) return [{'name_romaji': 'Director'}];
    throw StateError('Unexpected query: $sql');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MainDatabase main;
  late _R18Database r18;

  setUp(() {
    main = _MainDatabase();
    r18 = _R18Database();
    Get.put<DBService>(_Service()..dbMain = main..dbR18 = r18);
  });
  tearDown(Get.reset);

  test('repairs existing offline metadata without replacing local identity or user data', () async {
    final before = Map.of(main.row);
    expect(await HomePanelLibrary.repairVideoMetadata(Videos.fromJson(main.row)), isTrue);
    expect(main.row['video_code'], 'NAAC-066');
    expect(main.row['title'], 'New title');
    expect(main.row['poster'], 'New poster');
    expect(main.row['duration'], 120);
    expect(main.row['duration_formated'], '2 hours');
    expect(main.row['release_date'], '2026-09-29');
    expect(jsonDecode(main.row['actress'] as String).single['name_romaji'], 'Jane Doe');
    expect(jsonDecode(main.row['category'] as String).single['category'], 'Drama');
    expect(main.row['director'], 'Director');
    expect(jsonDecode(main.row['screenshot'] as String), hasLength(3));
    for (final key in ['id', 'root_path', 'video_path', 'is_favorite', 'view_count', 'filesize', 'quality', 'created_at', 'description']) {
      expect(main.row[key], before[key], reason: key);
      expect(main.updates.single.containsKey(key), isFalse, reason: key);
    }
  });

  test('missing catalog values retain existing metadata and unmatched videos stay untouched', () async {
    r18.emptyMetadata = true;
    expect(await HomePanelLibrary.repairVideoMetadata(Videos.fromJson(main.row)), isTrue);
    expect(main.row['poster'], 'Old poster');
    expect(main.row['duration'], 90);
    expect(main.row['duration_formated'], '1 hour, 30 minutes');
    expect(main.row['release_date'], '2025-01-01');
    expect(main.row['release_date_formated'], 'Jan 01, 2025');
    expect(main.updates.single.containsKey('actress'), isFalse);
    expect(main.updates.single.containsKey('category'), isFalse);
    expect(main.updates.single.containsKey('director'), isFalse);
    expect(await HomePanelLibrary.repairVideoMetadata(Videos(id: 'missing', videoPath: '/offline/ABP-99999.mp4')), isFalse);
    expect(await HomePanelLibrary.repairVideoMetadata(Videos(id: 'non-jav', videoPath: '/offline/ABP-001/holiday.mp4')), isFalse);
    expect(main.updates, hasLength(1));
  });

  test('unavailable or failed R18 reads never write local metadata', () async {
    final video = Videos.fromJson(main.row);
    Get.find<DBService>().dbR18 = null;
    expect(await HomePanelLibrary.repairVideoMetadata(video), isFalse);
    Get.find<DBService>().dbR18 = r18;
    r18.fail = true;
    await expectLater(HomePanelLibrary.repairVideoMetadata(video), throwsStateError);
    expect(main.updates, isEmpty);
  });
}
