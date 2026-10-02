import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_r18.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  _Database({this.rawRows = const [], this.queryRows = const []});

  List<Map<String, Object?>> rawRows;
  List<Map<String, Object?>> queryRows;
  final rawCalls = <_Call>[];
  final queryCalls = <_Call>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    rawCalls.add(_Call(sql, arguments ?? const []));
    return rawRows.map(Map<String, Object?>.from).toList();
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    queryCalls.add(_Call(where ?? '', whereArgs ?? const [], table: table, columns: columns, groupBy: groupBy, orderBy: orderBy, distinct: distinct));
    return queryRows.map(Map<String, Object?>.from).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call {
  _Call(this.sql, this.args, {this.table, this.columns, this.groupBy, this.orderBy, this.distinct});

  final String sql;
  final List<Object?> args;
  final String? table;
  final List<String>? columns;
  final String? groupBy;
  final String? orderBy;
  final bool? distinct;
}

/// Blacklist values are one sided patterns ('TK%' or '%BOD'), unlike search
/// patterns which are wrapped on both sides ('%school%').
List<Object?> _blacklistArgs(List<Object?> args) =>
    args.where((arg) => arg is String && arg.contains('%') && (arg.startsWith('%') != arg.endsWith('%'))).toList();

void main() {
  late _Database database;

  _Database attach({List<Map<String, Object?>> rawRows = const [], List<Map<String, Object?>> queryRows = const []}) {
    final db = _Database(rawRows: rawRows, queryRows: queryRows);
    Get.put<DBService>(_Service()..dbR18 = db);
    return db;
  }

  tearDown(Get.reset);

  group('without an R18 database', () {
    setUp(() => Get.put<DBService>(_Service()));

    test('every read degrades to an empty result instead of throwing', () async {
      expect(await DBR18.getCountAllVideos(), 0);
      expect(await DBR18.getVideo('ABP-001'), isNull);
      expect(await DBR18.getPosterByCodes(['ABP-001']), isEmpty);
      expect(await DBR18.search('abp'), isEmpty);
      expect(await DBR18.getSearchCount('abp'), 0);
      expect(await DBR18.getByFilter(), isEmpty);
      expect(await DBR18.getByFilterCount(), 0);
      expect(await DBR18.getAllActress(), isEmpty);
      expect(await DBR18.getActress('ABP-001'), isEmpty);
      expect(await DBR18.getAllSeries(), isEmpty);
      expect(await DBR18.getAllCategories(), isEmpty);
      expect(await DBR18.getCategory('ABP-001'), isEmpty);
      expect(await DBR18.getCategoriesByVideoCodes(['ABP-001']), isEmpty);
      expect(await DBR18.getDirector('ABP-001'), isNull);
      expect(await DBR18.getCountAllVideosByActress(1), 0);
      expect(await DBR18.getAllVideosByActress(1), isEmpty);
      expect(await DBR18.getCountAllVideosByCategory('Drama'), 0);
      expect(await DBR18.getAllVideosByCategory('Drama'), isEmpty);
      expect(await DBR18.getCountAllVideosByYear('2026'), 0);
      expect(await DBR18.getAllVideosByYear('2026'), isEmpty);
      expect(await DBR18.getNewRelease(), isEmpty);
    });
  });

  group('lookups', () {
    test('counts all videos and reads a single video by code', () async {
      database = attach(rawRows: [{'total': 12, 'id': 'abp00001', 'video_code': 'ABP-001'}]);

      expect(await DBR18.getCountAllVideos(), 12);
      expect(database.rawCalls.first.sql, contains('FROM derived_video v'));

      final video = await DBR18.getVideo('ABP-001');
      expect(video!['video_code'], 'ABP-001');
      expect(database.rawCalls.last.args, ['ABP-001']);
      expect(database.rawCalls.last.sql, contains('v.video_code = ?'));
      expect(database.rawCalls.last.sql, contains('LEFT JOIN machine_translation t'));
    });

    test('getVideo returns null when the code is unknown', () async {
      database = attach();
      expect(await DBR18.getVideo('NOPE-999'), isNull);
    });

    test('posters are looked up with trimmed unique codes and skip empty values', () async {
      database = attach(rawRows: [
        {'video_code': 'ABP-001', 'poster': 'https://img/abp001.jpg'},
        {'video_code': 'ABP-002', 'poster': ''},
        {'video_code': '', 'poster': 'https://img/orphan.jpg'},
      ]);

      final posters = await DBR18.getPosterByCodes([' ABP-001 ', 'ABP-001', 'ABP-002', '   ']);
      expect(posters, {'ABP-001': 'https://img/abp001.jpg'});
      expect(database.rawCalls.single.args, ['ABP-001', 'ABP-002']);
      expect(database.rawCalls.single.sql, contains('IN (?, ?)'));

      expect(await DBR18.getPosterByCodes([]), isEmpty);
      expect(await DBR18.getPosterByCodes(['   ']), isEmpty);
      expect(database.rawCalls, hasLength(1));
    });

    test('categories are grouped per video code, de-duplicated and sorted', () async {
      database = attach(rawRows: [
        {'video_code': 'ABP-001', 'category': 'Drama'},
        {'video_code': 'ABP-001', 'category': 'Big Tits'},
        {'video_code': 'ABP-001', 'category': 'Drama'},
        {'video_code': 'ABP-002', 'category': 'Cosplay'},
        {'video_code': '', 'category': 'Ignored'},
        {'video_code': 'ABP-003', 'category': ''},
      ]);

      final grouped = await DBR18.getCategoriesByVideoCodes([' ABP-001', 'ABP-001', 'ABP-002', 'ABP-003', '']);
      expect(grouped, {
        'ABP-001': ['Big Tits', 'Drama'],
        'ABP-002': ['Cosplay'],
      });
      expect(database.rawCalls.single.args, ['ABP-001', 'ABP-002', 'ABP-003']);

      expect(await DBR18.getCategoriesByVideoCodes([]), isEmpty);
      expect(await DBR18.getCategoriesByVideoCodes([' ', '']), isEmpty);
    });

    test('director and category lookups bind the requested code', () async {
      database = attach(rawRows: [{'id': 7, 'name_en': 'Some Director'}]);

      expect((await DBR18.getDirector('ABP-001'))!['name_en'], 'Some Director');
      expect(database.rawCalls.last.args, ['ABP-001']);

      await DBR18.getCategory('ABP-002');
      expect(database.rawCalls.last.args, ['ABP-002']);
      expect(database.rawCalls.last.sql, contains('cat.name_en IS NOT NULL'));

      await DBR18.getActress('ABP-003');
      expect(database.rawCalls.last.args, ['ABP-003']);
      expect(database.rawCalls.last.sql, contains('derived_video_actress'));
    });
  });

  group('search and filters', () {
    test('search binds canonical and compact queries, then filters, blacklist and paging', () async {
      database = attach();

      await DBR18.search('school', page: 3, perPage: 20);

      final call = database.rawCalls.single;
      expect(call.args.take(5), List.filled(5, '%school%'));
      expect(call.args.last, 40, reason: 'offset = (page - 1) * perPage');
      expect(call.args[call.args.length - 2], 20);
      expect(call.sql, contains('GROUP BY v.video_code'));
      expect(call.sql, contains('ORDER BY v.release_date DESC'));
      expect(call.sql, contains('LIMIT ? OFFSET ?'));
    });

    test('paging falls back to the first page and the default page size', () async {
      database = attach();

      await DBR18.search('x', page: null, perPage: null);
      expect(database.rawCalls.last.args.sublist(database.rawCalls.last.args.length - 2), [100, 0]);

      // Callers are expected to pass a 1 based page: page 0 is not clamped and
      // produces a negative offset.
      await DBR18.search('x', page: 0, perPage: 10);
      expect(database.rawCalls.last.args.last, -10);

      await DBR18.getByFilter(page: null, perPage: null);
      expect(database.rawCalls.last.args.sublist(database.rawCalls.last.args.length - 2), [100, 0]);

      await DBR18.getByFilter(page: 2, perPage: 50);
      expect(database.rawCalls.last.args.sublist(database.rawCalls.last.args.length - 2), [50, 50]);
    });

    test('every filter appends its own clause and bound values', () async {
      database = attach();

      await DBR18.getByFilter(
        videoCode: 'ABP',
        actressName: 'Yua',
        categories: ['Drama', 'Cosplay'],
        yearStart: 2020,
        yearEnd: 2024,
        durationMin: 60,
        durationMax: 180,
      );

      final call = database.rawCalls.single;
      expect(call.sql, contains('v.video_code LIKE ?'));
      expect(call.sql, contains('EXISTS ('));
      expect(call.sql, contains('da2.name_romaji LIKE ? OR da2.name_kana LIKE ? OR da2.name_kanji LIKE ?'));
      expect(call.sql, contains('dc2.name_en IN (?, ?)'));
      expect(call.sql, contains('CAST(substr(v.release_date, 1, 4) AS INTEGER) BETWEEN ? AND ?'));
      expect(call.sql, contains('v.runtime_mins > 0'));
      expect(call.sql, contains('v.runtime_mins >= ?'));
      expect(call.sql, contains('v.runtime_mins <= ?'));
      expect(call.sql, isNot(contains('HAVING COUNT(DISTINCT dc2.name_en)')));
      expect(call.args.take(12), ['%ABP%', '%ABP%', '%ABP%', '%Yua%', '%Yua%', '%Yua%', 'Drama', 'Cosplay', 2020, 2024, 60, 180]);
    });

    test('matchAllCategories adds the distinct category count to the clause', () async {
      database = attach(rawRows: [{'total': 0}]);

      await DBR18.getByFilterCount(categories: ['Drama', 'Cosplay', 'Drama'], matchAllCategories: true);

      final call = database.rawCalls.single;
      expect(call.sql, contains('GROUP BY vc2.content_id HAVING COUNT(DISTINCT dc2.name_en) = ?'));
      expect(call.args.take(4), ['Drama', 'Cosplay', 'Drama', 2], reason: 'the duplicate category is only counted once');
    });

    test('no filter means no extra clause at all', () async {
      database = attach(rawRows: [{'total': 5}]);

      expect(await DBR18.getByFilterCount(), 5);
      final call = database.rawCalls.single;
      expect(call.sql, isNot(contains('v.video_code LIKE ?')));
      expect(call.sql, isNot(contains('EXISTS (')));
      expect(call.sql, contains('COUNT(DISTINCT v.video_code) AS total'));
      expect(call.args, isNotEmpty, reason: 'the blacklist is always applied');
      expect(call.args.every((arg) => arg is String), isTrue);
    });

    test('a half open year range is ignored because both bounds are required', () async {
      database = attach();

      await DBR18.getByFilter(yearStart: 2020);
      expect(database.rawCalls.last.sql, isNot(contains('BETWEEN')));

      await DBR18.getByFilter(yearEnd: 2024);
      expect(database.rawCalls.last.sql, isNot(contains('BETWEEN')));
    });

    test('a single duration bound still forces a known runtime', () async {
      database = attach();

      await DBR18.getByFilter(durationMin: 90);
      expect(database.rawCalls.last.sql, contains('v.runtime_mins > 0'));
      expect(database.rawCalls.last.sql, contains('v.runtime_mins >= ?'));
      expect(database.rawCalls.last.sql, isNot(contains('v.runtime_mins <= ?')));

      await DBR18.getByFilter(durationMax: 90);
      expect(database.rawCalls.last.sql, contains('v.runtime_mins <= ?'));
      expect(database.rawCalls.last.sql, isNot(contains('v.runtime_mins >= ?')));
    });

    test('blacklisted prefixes and suffixes are excluded from every catalogue query', () async {
      database = attach(rawRows: [{'total': 0}]);

      await DBR18.search('x');
      final blacklist = _blacklistArgs(database.rawCalls.single.args);
      expect(blacklist, contains('TK%'));
      expect(blacklist, contains('PB%'));
      expect(blacklist, contains('%BOD'));
      expect(blacklist, contains('%DL'));
      expect(database.rawCalls.single.sql.split('v.video_code NOT LIKE ?').length - 1, blacklist.length);

      for (final call in [() => DBR18.getSearchCount('x'), () => DBR18.getByFilter(), () => DBR18.getAllVideosByYear('2026'), () => DBR18.getCountAllVideosByYear('2026')]) {
        database.rawCalls.clear();
        await call();
        expect(database.rawCalls.single.sql, contains('NOT LIKE ?'));
        expect(_blacklistArgs(database.rawCalls.single.args), contains('TK%'));
      }
    });
  });

  group('browsing', () {
    test('actress videos can opt out of the single actress restriction', () async {
      database = attach(rawRows: [{'total': 3}]);

      await DBR18.getAllVideosByActress(42, page: 2, perPage: 10);
      var call = database.rawCalls.last;
      expect(call.args.first, 42);
      expect(call.args.sublist(call.args.length - 2), [10, 10]);
      expect(call.sql, contains('HAVING COUNT(dva2.actress_id) = 1'));

      await DBR18.getAllVideosByActress(42, singleActressMode: false);
      call = database.rawCalls.last;
      expect(call.sql, isNot(contains('HAVING COUNT(dva2.actress_id) = 1')));
      expect(call.args.sublist(call.args.length - 2), [10000, 0]);

      expect(await DBR18.getCountAllVideosByActress(42), 3);
      expect(database.rawCalls.last.args.first, 42);
    });

    test('year browsing binds a prefix pattern', () async {
      database = attach(rawRows: [{'total': 9}]);

      expect(await DBR18.getCountAllVideosByYear('2024'), 9);
      expect(database.rawCalls.last.args.first, '2024%');

      await DBR18.getAllVideosByYear('2024', page: 3, perPage: 25);
      expect(database.rawCalls.last.args.first, '2024%');
      expect(database.rawCalls.last.args.sublist(database.rawCalls.last.args.length - 2), [25, 50]);
    });

    test('category browsing counts and lists with matching blacklist', () async {
      database = attach(rawRows: [{'total': 4}]);

      expect(await DBR18.getCountAllVideosByCategory('Drama'), 4);
      expect(database.rawCalls.last.args.first, 'Drama');
      expect(_blacklistArgs(database.rawCalls.last.args), contains('TK%'));

      await DBR18.getAllVideosByCategory('Drama');
      expect(database.rawCalls.last.args.first, 'Drama');
      expect(_blacklistArgs(database.rawCalls.last.args), contains('TK%'));
    });

    test('new releases are limited to the current month', () async {
      database = attach();

      await DBR18.getNewRelease(perPage: 10, page: 2);

      final call = database.rawCalls.single;
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      expect(call.args.first, '$month-01');
      expect(call.args[1], '$month-${now.day.toString().padLeft(2, '0')}');
      expect(call.args.sublist(call.args.length - 2), [10, 10]);
      expect(call.sql, contains('v.runtime_mins IS NOT NULL'));
      expect(call.sql, contains('v.label_id IS NOT NULL'));
    });
  });

  group('metadata lists', () {
    test('actress list filters out unusable names and can be searched', () async {
      database = attach(queryRows: [{'id': 1, 'name_en': 'Yua Mikami'}]);

      await DBR18.getAllActress();
      var call = database.queryCalls.single;
      expect(call.table, 'derived_actress');
      expect(call.orderBy, 'name_en COLLATE NOCASE');
      expect(call.groupBy, isNotNull);
      expect(call.sql, contains("name_romaji GLOB '[a-zA-Z]*'"));
      expect(call.sql, contains('LENGTH(name_romaji) >= 3'));
      expect(call.args, isEmpty);

      final result = await DBR18.getAllActress(q: 'yua');
      call = database.queryCalls.last;
      expect(result.single['name_en'], 'Yua Mikami');
      expect(call.args, ['%yua%', '%yua%', '%yua%']);
      expect(call.sql, contains('name_romaji LIKE ? OR name_kana LIKE ? OR name_kanji LIKE ?'));

      await DBR18.getAllActress(q: '   ');
      expect(database.queryCalls.last.args, isEmpty, reason: 'a blank search is ignored');
    });

    test('category list is distinct, grouped and optionally filtered', () async {
      database = attach(queryRows: [{'name_en': 'Drama'}]);

      await DBR18.getAllCategories();
      var call = database.queryCalls.single;
      expect(call.table, 'derived_category');
      expect(call.distinct, isTrue);
      expect(call.groupBy, 'name_en');
      expect(call.orderBy, 'name_en');
      expect(call.args, isEmpty);

      await DBR18.getAllCategories(q: 'dra');
      call = database.queryCalls.last;
      expect(call.sql, 'name_en IS NOT NULL AND name_en LIKE ?');
      expect(call.args, ['%dra%']);
    });

    test('series list keeps only series with a release and sorts by the newest one', () async {
      database = attach(rawRows: [{'id': 3, 'name_en': 'Some Series', 'max_release_date': '2026-01-01'}]);

      final all = await DBR18.getAllSeries();
      expect(all.single['name_en'], 'Some Series');
      expect(database.rawCalls.single.sql, contains('WHERE x.max_release_date IS NOT NULL'));
      expect(database.rawCalls.single.sql, contains('ORDER BY x.max_release_date DESC'));
      expect(database.rawCalls.single.args, isEmpty);

      await DBR18.getAllSeries(q: 'some');
      expect(database.rawCalls.last.args, ['%some%']);
      expect(database.rawCalls.last.sql, contains('AND s.name_en LIKE ?'));
    });
  });
}
