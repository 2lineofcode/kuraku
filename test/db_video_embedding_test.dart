import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_video_embedding.dart';
import 'package:sqflite/sqflite.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) => values[key] = value;

  @override
  Future<void> write(String key, dynamic value) async => writeInMemory(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];
  final queries = <Map<String, Object?>>[];
  final deletes = <String?>[];
  ConflictAlgorithm? lastConflict;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'video_embeddings');
    queries.add({'where': where, 'args': whereArgs, 'orderBy': orderBy, 'limit': limit});
    var found = where == null ? rows.toList() : rows.where((row) => row['video_id'] == whereArgs!.first).toList();
    if (orderBy == 'updated_at DESC') found.sort((a, b) => '${b['updated_at']}'.compareTo('${a['updated_at']}'));
    if (limit != null && found.length > limit) found = found.sublist(0, limit);
    return found.map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'video_embeddings');
    lastConflict = conflictAlgorithm;
    if (conflictAlgorithm == ConflictAlgorithm.replace) rows.removeWhere((row) => row['video_id'] == values['video_id']);
    rows.add(Map<String, Object?>.from(values));
    return rows.length;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final keys = ['video_id', 'source_text', 'embedding', 'model', 'created_at', 'updated_at'];
    final values = Map<String, Object?>.fromIterables(keys, arguments!);
    final existing = rows.where((row) => row['video_id'] == values['video_id']).firstOrNull;
    if (existing == null) {
      rows.add(values);
    } else {
      values['created_at'] = existing['created_at'];
      existing.addAll(values);
    }
    return rows.length;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(table, 'video_embeddings');
    deletes.add(where);
    final before = rows.length;
    rows.clear();
    return before;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    expect(sql, 'SELECT COUNT(*) as total FROM video_embeddings');
    return [{'total': rows.length}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  final preferences = _Preferences();
  final dateLike = RegExp(r'^\d{4}-\d{2}-\d{2}');

  setUpAll(() => Get.put(AppSettingService()..pref = preferences));
  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(() => Get.delete<DBService>(force: true));
  tearDownAll(Get.reset);

  group('VideoEmbeddingRecord', () {
    test('decodes a float32 blob column into doubles', () {
      final blob = Float32List.fromList([0.5, -0.25, 1]).buffer.asUint8List();
      final record = VideoEmbeddingRecord.fromJson({
        'video_id': 'v1',
        'source_text': 'title',
        'embedding': blob,
        'model': 'clip',
        'created_at': '2026-01-01 00:00:00',
        'updated_at': '2026-01-02 00:00:00',
      });

      expect(record.embedding, hasLength(3));
      expect(record.embedding[0], closeTo(0.5, 1e-6));
      expect(record.embedding[1], closeTo(-0.25, 1e-6));
      expect(record.embedding[2], closeTo(1, 1e-6));
      expect(record.videoId, 'v1');
      expect(record.model, 'clip');
    });

    test('decodes a JSON text column and falls back to an empty vector', () {
      final fromText = VideoEmbeddingRecord.fromJson({'video_id': 'v2', 'embedding': jsonEncode([1, 2.5, -3])});
      expect(fromText.embedding, [1.0, 2.5, -3.0]);
      expect(fromText.sourceText, '');
      expect(fromText.model, '');
      expect(fromText.createdAt, '');
      expect(fromText.updatedAt, '');

      expect(VideoEmbeddingRecord.fromJson({'embedding': ''}).embedding, isEmpty);
      expect(VideoEmbeddingRecord.fromJson({}).embedding, isEmpty);
      expect(VideoEmbeddingRecord.fromJson({}).videoId, '');
    });

    test('serialises the vector as a little-endian float32 blob', () {
      final json = VideoEmbeddingRecord(videoId: 'v3', sourceText: 'text', embedding: [0.1, 0.2], model: 'm', createdAt: 'c', updatedAt: 'u').toJson();
      expect(json['embedding'], isA<Uint8List>());
      final decoded = VideoEmbeddingRecord.fromJson(json);
      expect(decoded.embedding[0], closeTo(0.1, 1e-6));
      expect(decoded.embedding[1], closeTo(0.2, 1e-6));
    });
  });

  group('DBVideoEmbeddings', () {
    test('upsert updates the row, keeps the original creation date and defaults the model', () async {
      await DBVideoEmbeddings.upsert(videoId: 'v1', sourceText: 'first text', embedding: [0.1, 0.2]);
      expect(database.rows, hasLength(1));
      expect(database.lastConflict, isNull);
      expect(database.rows.single['model'], 'local-hash-v2');
      expect('${database.rows.single['created_at']}', matches(dateLike));
      final createdAt = database.rows.single['created_at'];

      database.rows.single['created_at'] = '2020-01-01 00:00:00';
      database.rows.single['updated_at'] = '2020-01-01 00:00:00';
      await DBVideoEmbeddings.upsert(videoId: 'v1', sourceText: 'second text', embedding: [0.3], model: 'clip-vit');

      expect(database.rows, hasLength(1));
      expect(database.rows.single['source_text'], 'second text');
      expect(database.rows.single['model'], 'clip-vit');
      expect(database.rows.single['created_at'], '2020-01-01 00:00:00');
      expect(database.rows.single['updated_at'], isNot('2020-01-01 00:00:00'));
      expect(createdAt, isNotNull);
    });

    test('upsert uses the configured semantic search model when one is stored', () async {
      preferences.values['_kSemanticSearchModel'] = 'clip-b32';
      addTearDown(() => preferences.values.remove('_kSemanticSearchModel'));

      await DBVideoEmbeddings.upsert(videoId: 'v9', sourceText: 'text', embedding: [1]);
      expect(database.rows.single['model'], 'clip-b32');
    });

    test('reads a single embedding, the full list and the row count', () async {
      await DBVideoEmbeddings.upsert(videoId: 'v1', sourceText: 'one', embedding: [1, 2]);
      await DBVideoEmbeddings.upsert(videoId: 'v2', sourceText: 'two', embedding: [3]);
      database.rows[0]['updated_at'] = '2026-01-01 00:00:00';
      database.rows[1]['updated_at'] = '2026-02-01 00:00:00';

      final single = await DBVideoEmbeddings.getByVideoId('v1');
      expect(single!.sourceText, 'one');
      expect(single.embedding, [1.0, 2.0]);
      expect(database.queries.last['where'], 'video_id = ?');
      expect(database.queries.last['limit'], 1);
      expect(await DBVideoEmbeddings.getByVideoId('missing'), isNull);

      final all = await DBVideoEmbeddings.getAll();
      expect(all.map((e) => e.videoId), ['v2', 'v1']);
      expect(database.queries.last['orderBy'], 'updated_at DESC');
      expect(await DBVideoEmbeddings.getCount(), 2);
    });

    test('deleteAll wipes the table without a filter', () async {
      await DBVideoEmbeddings.upsert(videoId: 'v1', sourceText: 'one', embedding: [1]);
      await DBVideoEmbeddings.deleteAll();

      expect(database.rows, isEmpty);
      expect(database.deletes.single, isNull);
      expect(await DBVideoEmbeddings.getCount(), 0);
    });
  });
}
