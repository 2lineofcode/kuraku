import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../utils/helper.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';

mixin DBVideos {
  static Database get _db => Get.find<DBService>().dbMain;
  static final _tableName = 'videos';
  static const _allowedColumns = {
    'id', 'root_path', 'video_path', 'video_code', 'title', 'title_ja',
    'description', 'fan_art', 'poster', 'trailer', 'actress', 'category',
    'release_date', 'release_date_formated', 'duration', 'duration_formated', 'studio', 
    'label', 'director', 'series', 'screenshot', 'view_count', 'site',
    'is_favorite', 'filesize', 'quality', 'created_at', 'updated_at',
  };

  static String _safeColumn(String column) {
    if (_allowedColumns.contains(column)) return column;
    throw ArgumentError('Unsupported column: $column');
  }

  static Future<bool> _validation(Videos videos) async {
    final isDuplicateVideoPath = await getByVideoPath(videos.videoPath ?? '');
    if (isDuplicateVideoPath != null) return false;
    return true;
  }

  static Future<void> addBulk(List<Videos> videos) async {
    final List<Map<String, dynamic>> videosToInsert = [];

    for (int i = 0; i < videos.length; i++) {
      final video = videos[i];

      // ** default
      video.id = const UuidV4().generate();
      video.createdAt = DateTime.now().toStringEx();
      video.updatedAt = DateTime.now().toStringEx();

      // decensored fix `category`// Decensor and format data
      if (video.category != null) {
        for (int j = 0; j < video.category!.length; j++) {
          final dec = HelperDecensor.decensor(video.category![j].category);
          video.category![j].category = dec;
        }
      }
      
      // decensored fix `series`
      if (video.series.isNotEmptyAndNotNull) {
        final dec = HelperDecensor.decensor(video.series);
        video.series = dec;
      }

      // actress
      if (video.actress != null) {
        for (int j = 0; j < video.actress!.length; j++) {
          if (video.actress![j].nameRomaji == '') {
            video.actress![j].nameRomaji = video.actress![j].imageUrl;
          }
          video.actress![j].nameRomaji = HelperMisc.formatActressName(video.actress![j].nameRomaji ?? '');
        }
      }

      // Check validation
      final isOK = await _validation(video);
      if (isOK) videosToInsert.add(video.toJson());
      
    }

    // 2. Perform a single database transaction for insertion
    if (videosToInsert.isNotEmpty) {
      await _db.transaction((txn) async {
        for (final videoJson in videosToInsert) {
          await txn.insert(_tableName, videoJson, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      AppLog.logD('bulkAdd: ${videosToInsert.length} videos');
    }
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

  static Future<List<Videos>> getAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    String? groupBy,
    int? limit
  }) async {
    try {
      final maps = await _db.query(_tableName, where: where, whereArgs: whereArgs, groupBy: groupBy, orderBy: orderBy, limit: limit);
      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> getAllLike(String column, String like, {String? jsonObject}) async {
    var part = '';
    if (jsonObject != null) part = '"$jsonObject":"';
    final safeColumn = _safeColumn(column);
    final likeQuery = '%$part$like%';

    try {
      final maps = await _db.rawQuery('''
        SELECT * FROM $_tableName
        WHERE 1=1
          AND $safeColumn LIKE ?
        ORDER BY release_date DESC
      ''', [likeQuery]);

      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> getAllVideoPath(String column, String like) async {
    final safeColumn = _safeColumn(column);
    final pathPrefix = '$like%';
    final nestedPrefix = '$like/%/%';

    try {
      final maps = await _db.rawQuery('''
        SELECT * FROM $_tableName
        WHERE 1=1
          AND $safeColumn LIKE ? 
          AND $safeColumn NOT LIKE ?
        ORDER BY video_code ASC, title ASC
      ''', [pathPrefix, nestedPrefix]);

      return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
    } catch (e) {
      throw Exception('${e.toString()}');
    }
  }

  static Future<List<Videos>> search(String s) async {
    final query = '%$s%';
    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName 
      WHERE 1=1
        AND (
          video_code LIKE ?
          OR title LIKE ?
          OR video_path LIKE ?
        )
    ''', [query, query, query]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  // ** get_by
  static Future<Videos> getByID(String id) async {
    final maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return Videos.fromJson(maps.first);
  }

  static Future<Videos> getByCode(String code) async {
    final maps = await _db.query(_tableName, where: 'video_code = ?', whereArgs: [code]);
    return Videos.fromJson(maps.first);
  }

  static Future<Videos?> getByVideoPath(String videoPath) async {
    final maps = await _db.query(_tableName, where: 'video_path = ?', whereArgs: [videoPath]);
    return maps.isNotEmpty ? Videos.fromJson(maps.first) : null;
  }

  static Future<List<Videos>> getBySeries(String series) async {
    final maps = await _db.query(_tableName, where: 'series = ?', whereArgs: [series]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

   static Future<List<Videos>> getByActress(String actressName) async {
    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName WHERE json_extract(actress, '\$[0].name_romaji') LIKE ?
    ''', ['%$actressName%']);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  // ** end get_by

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
    upd.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  static Future<void> removeFromFavorite(Videos video) async {
    final upd = video;
    upd.isFavorite = 0;
    upd.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ helper
  static Future<void> deleteAll() async => await _db.delete(_tableName);
  static Future<void> vacuum() async {
    await _db.rawQuery('VACUUM');
    AppLog.logD('VACUUM Done.');
  }


  static Future<String> getRandomVideoCode() async {
    final maps = await _db.query(_tableName, orderBy: 'RANDOM()', limit: 1, where: 'video_code IS NOT NULL AND video_code != ""');
    if (maps.isEmpty) return 'Search by Code or Title...';
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
      SELECT DISTINCT 
        studio AS name, 
        COUNT(studio) AS count
      FROM $_tableName
      WHERE 1=1
        AND studio IS NOT NULL 
        AND studio != ''
      GROUP BY studio;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Label ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllLabelWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT 
        label AS name, 
        COUNT(label) AS count
      FROM $_tableName
      WHERE 1=1
        AND label IS NOT NULL 
        AND label != ''
      GROUP BY label;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Series ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllSeriesWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT 
        series AS name, 
        COUNT(series) AS count
      FROM $_tableName
      WHERE 1=1
        AND series IS NOT NULL 
        AND series != ''
      GROUP BY series;
    ''');
    final maps = List<Map<String, dynamic>>.from(rawMaps);
    maps.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return maps;
  }

  // Director ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllDirectorWithCount() async {
    final rawMaps = await _db.rawQuery('''
      SELECT DISTINCT 
        director AS name, 
        COUNT(director) AS count
      FROM $_tableName
      WHERE 1=1 
        AND director IS NOT NULL 
        AND director != ''
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
      FROM $_tableName
      WHERE 1=1
        AND release_date IS NOT NULL 
        AND release_date != ''
      GROUP BY
        STRFTIME('%Y', release_date)
      ORDER BY
        name DESC
      ;
    ''');

    final maps = List<Map<String, dynamic>>.from(rawMaps);
    return maps;
  }


  static Future<List<Videos>> getListDuplicateVideos() async {
    final maps = await _db.rawQuery('''
        SELECT * FROM $_tableName v
        WHERE v.video_code IN (
          SELECT video_code
          FROM $_tableName
          WHERE video_code != '' AND video_code IS NOT NULL
          GROUP BY video_code
          HAVING COUNT(video_code) > 1
        )
        ORDER BY 
          v.video_code, v.video_path;
      ''');
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }


  static Future<num?> getTotalFileSizeAllVideo() async {
    final maps = await _db.rawQuery('SELECT sum(filesize) as total FROM videos');
    return maps.first['total'] as num?;
  }
}
