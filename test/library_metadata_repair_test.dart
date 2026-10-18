import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/__kuraku_metadata_entity.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_library.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _MainDatabase implements Database, Transaction {
  final row = <String, Object?>{
    'id': 'local-id', 'root_path': '/offline', 'video_path': '/offline/NAAC-066.mp4',
    'video_code': '', 'title': 'Old title', 'description': 'Custom description',
    'poster': 'Old poster', 'duration': 90, 'duration_formated': '1 hour, 30 minutes',
    'release_date': '2025-01-01', 'release_date_formated': 'Jan 01, 2025',
    'is_favorite': 1, 'view_count': 42, 'filesize': 12345, 'quality': '1920x1080',
    'created_at': '2025-01-01', 'actress': null, 'category': null, 'screenshot': null,
  };
  final updates = <Map<String, Object?>>[];
  bool failWrites = false;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
    whereArgs![0] == row['id'] && whereArgs[1] == row['video_path'] ? [Map.of(row)] : [];

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    if (failWrites) throw StateError('Database unavailable');
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
    if (sql.contains('derived_director')) return [{'director': 'Director'}];
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

  test('API refresh retains missing values and never changes the source or local identity', () async {
    main.row.addAll({
      'actress': '[{"id":1,"name_romaji":"Local Cast"}]',
      'category': '[{"id":1,"category":"Drama"}]',
      'screenshot': '["local-shot"]',
    });
    final source = Videos.fromJson(main.row);
    final before = Map.of(main.row);
    final metadata = Videos.fromMetadata(KurakuMetadata(
      title: 'Updated title', description: ' null ', poster: '   ',
      actress: [KurakuMetadataActors(castNames: '', castImage: '')],
      genre: ['', ' null '], screenshot: ['', ' null '],
      duration: 0, durationFormated: 'Invalid new duration',
      releaseDate: '', releaseDateFormated: 'Invalid new date',
    ));
    final revision = DBVideos.revision.value;
    expect(await DBVideos.updateMetadata(source, metadata), 1);
    expect(main.row['title'], 'Updated title');
    for (final key in ['id', 'root_path', 'video_path', 'is_favorite', 'view_count', 'filesize', 'quality', 'created_at',
      'description', 'poster', 'actress', 'category', 'screenshot', 'duration', 'duration_formated', 'release_date', 'release_date_formated']) {
      expect(main.row[key], before[key], reason: key);
      expect(main.updates.single.containsKey(key), isFalse, reason: key);
    }
    expect(source.title, 'Old title');
    expect(source.actress!.single.nameRomaji, 'Local Cast');
    expect(DBVideos.revision.value, revision + 1);
  });

  test('API mapping keeps images and cast and computes display values from new raw values', () async {
    final metadata = Videos.fromMetadata(KurakuMetadata(
      videoCode: 'NAAC-066', title: 'Updated title',
      fanArt: 'https://pics.dmm.co.jp/digital/video/naac00066/naac00066pl.jpg',
      poster: 'https://pics.dmm.co.jp/digital/video/naac00066/naac00066ps.jpg',
      actress: [KurakuMetadataActors(castId: 123, castNames: 'jane doe', castImage: 'cast.jpg')],
      genre: ['Drama'], screenshot: [
        'https://pics.dmm.co.jp/digital/video/naac00066/naac00066jp-1.jpg',
        'https://pics.dmm.co.jp/digital/video/naac00066/naac00066-2.jpg',
      ],
      duration: 125, releaseDate: '2026-10-01',
    ));
    expect(await DBVideos.updateMetadata(Videos.fromJson(main.row), metadata), 1);
    expect(main.row['fan_art'], 'digital/video/naac00066/naac00066pl');
    expect(main.row['poster'], 'digital/video/naac00066/naac00066ps');
    expect(jsonDecode(main.row['actress'] as String).single, containsPair('name_romaji', 'Jane Doe'));
    expect(jsonDecode(main.row['category'] as String).single, containsPair('category', 'Drama'));
    expect(jsonDecode(main.row['screenshot'] as String), [
      'digital/video/naac00066/naac00066jp-1', 'digital/video/naac00066/naac00066jp-2',
    ]);
    expect(main.row['duration_formated'], '2 hours, 5 minutes');
    expect(main.row['release_date_formated'], 'Oct 01, 2026');
  });

  test('failed and stale refreshes leave source metadata and revision unchanged', () async {
    final source = Videos.fromJson(main.row);
    final before = Map.of(main.row);
    final metadata = Videos.fromMetadata(KurakuMetadata(title: 'Updated title'));
    final revision = DBVideos.revision.value;
    main.failWrites = true;
    await expectLater(DBVideos.updateMetadata(source, metadata), throwsStateError);
    expect(main.row, before);
    expect(source.title, 'Old title');
    expect(DBVideos.revision.value, revision);
    main.failWrites = false;
    expect(await DBVideos.updateMetadata(Videos(id: 'stale', videoPath: source.videoPath), metadata), 0);
    expect(DBVideos.revision.value, revision);
  });

  test('repair batches suppress per-video refresh notifications', () async {
    final revision = DBVideos.revision.value;
    expect(await HomePanelLibrary.repairVideoMetadata(Videos.fromJson(main.row)), isTrue);
    expect(DBVideos.revision.value, revision);
  });

  test('invalid incoming dates never partially overwrite metadata', () async {
    final before = Map.of(main.row);
    final metadata = Videos.fromMetadata(KurakuMetadata(title: 'Updated title', releaseDate: '2026-02-30'));
    await expectLater(DBVideos.updateMetadata(Videos.fromJson(main.row), metadata), throwsFormatException);
    expect(main.row, before);
    expect(main.updates, isEmpty);
  });

  test('metadata repair keeps cast with Japanese-only names', () async {
    for (final actress in [
      VideoActress(id: 7, nameRomaji: '', nameKana: 'ユア', imageUrl: 'https://pics.dmm.co.jp/mono/actjpgs/mikami_yua.jpg'),
      VideoActress(id: 8, nameRomaji: null, nameKanji: '三上悠亜', imageUrl: 'https://pics.dmm.co.jp/mono/actjpgs/mikami_yua.jpg'),
    ]) {
      expect(await DBVideos.updateMetadata(Videos.fromJson(main.row), Videos(actress: [actress])), 1);
      final saved = jsonDecode(main.row['actress'] as String) as List;
      expect(saved.single['name_romaji'], '');
      expect(saved.single['name_kana'], actress.nameKana);
      expect(saved.single['name_kanji'], actress.nameKanji);
    }
  });

  test('missing cast names are inferred from photo filenames instead of absolute URLs', () async {
    for (final name in [null, '', '   ']) {
      final metadata = Videos.fromMetadata(KurakuMetadata(actress: [
        KurakuMetadataActors(castId: 7, castNames: name,
          castImage: 'https://pics.dmm.co.jp/mono/actjpgs/mikami_yua123.jpg?version=2'),
      ]));
      expect(await DBVideos.updateMetadata(Videos.fromJson(main.row), metadata), 1);
      final saved = jsonDecode(main.row['actress'] as String) as List;
      expect(saved.single['name_romaji'], 'Yua Mikami');
      expect(saved.single['image_url'], 'https://pics.dmm.co.jp/mono/actjpgs/mikami_yua123.jpg?version=2');
    }
  });

}
