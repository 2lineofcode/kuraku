import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../utils/helper_misc.dart';
import '../models/videos_entity.dart';
import 'db_init.dart';

mixin DBVideos {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'Videos';

  static Future<bool> _validation(Videos videos) async {
    final isDuplicateVideoPath = await getByVideoPath(videos.videoPath ?? '');
    if (isDuplicateVideoPath.isNotEmpty) return false;
    return true;
  }

  static Future<void> add(Videos videos) async {
    videos.id = UuidV4().generate();
    videos.createdAt = DateTime.now().toStringEx();
    videos.updatedAt = DateTime.now().toStringEx();

    // decensored fix `category`
    if (videos.category != null) {
      for (int i = 0; i < videos.category!.length; i++) {
        final dec = await HelperMisc.decensor(videos.category![i].category ?? '');
        videos.category![i].category = dec;
      }
    }

    // decensored fix `series`
    if (videos.series.isNotEmptyAndNotNull) {
      final dec = await HelperMisc.decensor(videos.series);
      videos.series = dec;
    }

    // actress
    if (videos.actress != null) {
      for (int i = 0; i < videos.actress!.length; i++) {
        if (videos.actress![i].nameRomaji == '') {
          videos.actress![i].nameRomaji = videos.actress![i].imageUrl;
        }
        videos.actress![i].nameRomaji = HelperMisc.formatName(videos.actress![i].nameRomaji ?? '');
      }
    }

    final isOK = await _validation(videos);
    if (isOK) await _db.insert(_tableName, videos.toJson());
  }

  static Future<void> update(Videos videos) async {
    videos.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, videos.toJson(), where: 'id = ?', whereArgs: [videos.id]);
  }

  static Future<void> delete(Videos videos) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [videos.id]);
  }

  static Future<void> deleteByVideoPath(String videoPath) async {
    await _db.delete(_tableName, where: 'video_path = ?', whereArgs: [videoPath]);
  }

  static Future<void> deleteByRootPath(String rootPath) async {
    await _db.delete(_tableName, where: 'root_path = ?', whereArgs: [rootPath]);
  }

  static Future<List<Videos>> getAll({String? where, List<Object?>? whereArgs, int? limit}) async {
    try {
      final maps = await _db.query(_tableName, where: where, whereArgs: whereArgs, limit: limit);
      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> getAllLike(String column, String like, {String? jsonObject}) async {
    var part = '';
    if (jsonObject != null) part = '"$jsonObject":"';

    try {
      final maps = await _db.rawQuery('''
        SELECT * FROM $_tableName
        WHERE 1=1
        AND $column LIKE '%$part$like%'
      ''');

      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> getAllVideoPath(String column, String like) async {
    try {
      final maps = await _db.rawQuery('''
        SELECT * FROM Videos
        WHERE $column 
        LIKE '$like%' AND $column NOT LIKE '$like/%/%';
      ''');

      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> getByID(String id) async {
    final maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> getByCode(String code) async {
    final maps = await _db.query(_tableName, where: 'video_code = ?', whereArgs: [code]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> search(String s) async {
    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName 
      WHERE 1=1
        AND video_code LIKE '%$s%'
        OR title LIKE '%$s%'
        OR video_path LIKE '%$s%'
    ''', [s]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> getByVideoPath(String videoPath) async {
    final maps = await _db.query(_tableName, where: 'video_path = ?', whereArgs: [videoPath]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> updateViewCount(Videos video) async {
    final upd = video;
    upd.viewCount = video.viewCount! + 1;
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  static Future<void> addToFavorite(Videos video) async {
    final upd = video;
    upd.isFavorite = 1;
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  static Future<void> removeFromFavorite(Videos video) async {
    final upd = video;
    upd.isFavorite = 0;
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ helper
  static Future<void> deleteAll() async => await _db.delete(_tableName);

  static Future<String> getRandomVideoCode() async {
    final maps = await _db.query(_tableName, orderBy: 'RANDOM()', limit: 1, where: 'video_code IS NOT NULL AND video_code != ""');
    if (maps.isEmpty) return 'Search...';
    return maps.first['video_code'] as String;
  }

  // Category ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllCategoryWithCount() async {
    final categoryIdToCount = {};
    final uniqueCategory = {};

    final rawData = await _db.rawQuery('SELECT category FROM $_tableName');

    for (var row in rawData) {
      final categoryString = row['category'] as String?;

      if (categoryString != null && categoryString.isNotEmpty) {
        try {
          final categoryJson = jsonDecode(categoryString);
          final Set<String> categoryInThisVideo = {};

          for (var categoryMap in categoryJson) {
            if (categoryMap is Map<String, dynamic>) {
              final currentCategory = VideoCategory.fromJson(categoryMap);
              if (currentCategory.category != null) {
                uniqueCategory.putIfAbsent(currentCategory.category!, () => currentCategory);

                if (!categoryInThisVideo.contains(currentCategory.category!)) {
                  categoryIdToCount[currentCategory.category!] = (categoryIdToCount[currentCategory.category!] ?? 0) + 1;
                  categoryInThisVideo.add(currentCategory.category!);
                }
              }
            }
          }
        } catch (e) {
          AppLog.logE('Error parsing category JSON: $e for string: $categoryString');
        }
      }
    }

    final result = <Map<String, dynamic>>[];
    uniqueCategory.forEach((id, col) {
      result.add({
        'id': col.id,
        'name': col.category,
        'count': categoryIdToCount[id] ?? 0,
      });
    });
    result.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  // Actress ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllActressWithCount() async {
    final actressIdToCount = {};
    final uniqueActresses = {};

    final rawData = await _db.rawQuery('SELECT actress FROM $_tableName');

    for (var row in rawData) {
      final actressString = row['actress'] as String?;

      if (actressString != null && actressString.isNotEmpty) {
        try {
          final actressesJson = jsonDecode(actressString);
          final Set<num> actressesInThisVideo = {};

          for (var actressMap in actressesJson) {
            if (actressMap is Map<String, dynamic>) {
              final currentActress = VideoActress.fromJson(actressMap);
              if (currentActress.id != null) {
                uniqueActresses.putIfAbsent(currentActress.id!, () => currentActress);

                if (!actressesInThisVideo.contains(currentActress.id!)) {
                  actressIdToCount[currentActress.id!] = (actressIdToCount[currentActress.id!] ?? 0) + 1;
                  actressesInThisVideo.add(currentActress.id!);
                }
              }
            }
          }
        } catch (e) {
          AppLog.logE('Error parsing actress JSON: $e for string: $actressString');
        }
      }
    }

    final result = <Map<String, dynamic>>[];
    uniqueActresses.forEach((id, col) {
      result.add({
        'id': col.id,
        'nameRomaji': col.nameRomaji,
        'nameKanji': col.nameKanji,
        'nameKana': col.nameKana,
        'imageUrl': col.imageUrl,
        'count': actressIdToCount[id] ?? 0,
      });
    });

    result.sort((a, b) => (a['nameRomaji'] as String).compareTo(b['nameRomaji'] as String));
    return result;
  }

  // Studio ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllStudioWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT studio AS name, COUNT(studio) AS count
      FROM Videos
      WHERE studio IS NOT NULL AND studio != ''
      GROUP BY studio;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Label ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllLabelWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT label AS name, COUNT(label) AS count
      FROM Videos
      WHERE label IS NOT NULL AND label != ''
      GROUP BY label;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Series ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllSeriesWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT series AS name, COUNT(series) AS count
      FROM Videos
      WHERE series IS NOT NULL AND series != ''
      GROUP BY series;
    ''');
    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Director ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllDirectorWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT director AS name, COUNT(director) AS count
      FROM Videos
      WHERE director IS NOT NULL AND director != ''
      GROUP BY director;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Video Path ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllPathWithCount() async {
    final rawData = await _db.rawQuery('SELECT video_path FROM $_tableName');
    final Map<String, int> directoryCounts = {};
    for (var row in rawData) {
      final String? videoPath = row['video_path'] as String?;
      if (videoPath != null && videoPath.isNotEmpty) {
        final directory = p.dirname(videoPath);
        directoryCounts[directory] = (directoryCounts[directory] ?? 0) + 1;
      }
    }

    final result = <Map<String, dynamic>>[];
    directoryCounts.forEach((directory, count) {
      result.add({
        'name': directory,
        'count': count,
      });
    });

    result.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  // ReleaseYear ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllReleaseYearWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT
        STRFTIME('%Y', release_date) AS name,
        COUNT(*) AS count
      FROM Videos
      WHERE
        release_date IS NOT NULL AND release_date != ''
      GROUP BY
        STRFTIME('%Y', release_date)
      ORDER BY
        name DESC
      ;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    return maps;
  }
}
