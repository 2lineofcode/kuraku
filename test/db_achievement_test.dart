import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_achievement.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];
  final queries = <Map<String, Object?>>[];
  Object? totalOverride;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'achievement_unlock');
    queries.add({'where': where, 'args': whereArgs, 'orderBy': orderBy, 'limit': limit});
    var found = where == null ? rows.toList() : rows.where((row) => row['achievement_key'] == whereArgs!.first).toList();
    if (orderBy == 'unlocked_at DESC') found.sort((a, b) => '${b['unlocked_at'] ?? ''}'.compareTo('${a['unlocked_at'] ?? ''}'));
    if (limit != null && found.length > limit) found = found.sublist(0, limit);
    return found.map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'achievement_unlock');
    rows.add(Map<String, Object?>.from(values));
    return rows.length;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    expect(sql, 'SELECT COUNT(*) AS total FROM achievement_unlock');
    return [{'total': totalOverride ?? rows.length}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  final dateLike = RegExp(r'^\d{4}-\d{2}-\d{2}');

  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(Get.reset);

  test('unlocking an achievement writes it once and reports whether it was new', () async {
    expect(await DBAchievement.unlock(key: 'first_play', title: 'First Play', description: 'Played your first video'), isTrue);
    expect(await DBAchievement.unlock(key: 'first_play', title: 'First Play', description: 'Played again'), isFalse);
    expect(database.rows, hasLength(1));

    final stored = database.rows.single;
    expect(stored['achievement_key'], 'first_play');
    expect(stored['title'], 'First Play');
    expect(stored['description'], 'Played your first video');
    expect('${stored['id']}', hasLength(36));
    expect('${stored['unlocked_at']}', matches(dateLike));
    expect(stored['created_at'], stored['unlocked_at']);
    expect(stored['updated_at'], stored['unlocked_at']);
  });

  test('isUnlocked only matches the exact key and stops at the first row', () async {
    await DBAchievement.unlock(key: 'night_owl', title: 'Night Owl', description: 'Watched late');

    expect(await DBAchievement.isUnlocked('night_owl'), isTrue);
    expect(await DBAchievement.isUnlocked('NIGHT_OWL'), isFalse);
    expect(await DBAchievement.isUnlocked('missing'), isFalse);
    expect(database.queries.last['where'], 'achievement_key = ?');
    expect(database.queries.last['limit'], 1);
  });

  test('counts unlocked achievements and tolerates a null or floating point total', () async {
    expect(await DBAchievement.countUnlocked(), 0);

    await DBAchievement.unlock(key: 'a', title: 'A', description: 'a');
    await DBAchievement.unlock(key: 'b', title: 'B', description: 'b');
    expect(await DBAchievement.countUnlocked(), 2);

    database.totalOverride = 7.0;
    expect(await DBAchievement.countUnlocked(), 7);
    database.totalOverride = null;
    expect(await DBAchievement.countUnlocked(), 2);
  });

  test('lists unlocks newest first, honours the limit and never returns null fields', () async {
    database.rows.addAll([
      {'id': 1, 'achievement_key': 'old', 'title': 'Old', 'description': 'first', 'unlocked_at': '2026-01-01 00:00:00'},
      {'id': 2, 'achievement_key': 'new', 'title': 'New', 'description': 'second', 'unlocked_at': '2026-05-01 00:00:00'},
      {'achievement_key': null, 'title': null, 'description': null, 'unlocked_at': null},
    ]);

    final all = await DBAchievement.getAll();
    expect(all.map((e) => e.achievementKey), ['new', 'old', '']);
    expect(all.first.id, '2');
    expect(all.first.title, 'New');
    expect(all.last.title, '');
    expect(all.last.description, '');
    expect(all.last.unlockedAt, '');

    final limited = await DBAchievement.getAll(limit: 1);
    expect(limited, hasLength(1));
    expect(limited.single.achievementKey, 'new');
    expect(database.queries.last['limit'], 1);
    expect(database.queries.last['orderBy'], 'unlocked_at DESC');
  });
}
