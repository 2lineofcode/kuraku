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
  static const _tableName = 'videos';
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

  static List<Videos> _toVideos(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
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

  static Future<int> recoverMissingVideoCodes(String rootPath) async {
    if (rootPath.isEmpty) return 0;
    return _db.transaction((txn) async {
      const missingCode = "(video_code IS NULL OR TRIM(video_code) = '')";
      final rows = await txn.query(_tableName, columns: ['id', 'video_path'], where: 'root_path = ? AND $missingCode', whereArgs: [rootPath]);
      var recovered = 0;
      for (final row in rows) {
        final code = (row['video_path'] as String? ?? '').getFileName().getVideoCode();
        if (!code.isValidVideoCode()) continue;
        recovered += await txn.update(_tableName, {'video_code': code}, where: 'id = ? AND $missingCode', whereArgs: [row['id']]);
      }
      return recovered;
    });
  }

  static Future<void> delete(Videos videos) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [videos.id]);
  }

  static Future<void> deleteByVideoPath(String videoPath) async {
    await _db.delete(_tableName, where: 'video_path = ?', whereArgs: [videoPath]);
  }

  static Future<void> deleteByVideoPaths(List<String> videoPaths) async {
    if (videoPaths.isEmpty) return;
    final unique = videoPaths.where((p) => p.trim().isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;

    // Keep below SQLite variable limit.
    const chunkSize = 800;
    await _db.transaction((txn) async {
      for (var i = 0; i < unique.length; i += chunkSize) {
        final chunk = unique.sublist(i, i + chunkSize > unique.length ? unique.length : i + chunkSize);
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.rawDelete(
          'DELETE FROM $_tableName WHERE video_path IN ($placeholders)',
          chunk,
        );
      }
    });
  }

  static Future<void> deleteByRootPath(String rootPath) async {
    await _db.delete(_tableName, where: 'root_path = ?', whereArgs: [rootPath]);
  }

  static Future<int> moveVideoPaths(List<Map<String, String>> moves) async {
    if (moves.isEmpty) return 0;
    var updatedRows = 0;
    final now = DateTime.now().toStringEx();

    await _db.transaction((txn) async {
      for (final move in moves) {
        final oldPath = (move['oldPath'] ?? '').trim();
        final newPath = (move['newPath'] ?? '').trim();
        final newRoot = (move['newRoot'] ?? '').trim();
        if (oldPath.isEmpty || newPath.isEmpty || newRoot.isEmpty) continue;

        final affected = await txn.rawUpdate(
          '''
          UPDATE $_tableName
          SET video_path = ?, root_path = ?, updated_at = ?
          WHERE video_path = ?
          ''',
          [newPath, newRoot, now, oldPath],
        );
        updatedRows += affected;
      }
    });

    return updatedRows;
  }

  static Future<List<Videos>> getAll({String? where, List<Object?>? whereArgs, String? orderBy, String? groupBy, int? limit}) async {
    final maps = await _db.query(_tableName, where: where, whereArgs: whereArgs, groupBy: groupBy, orderBy: orderBy, limit: limit);
    return _toVideos(maps);
  }

  static Future<List<Videos>> getAllLike(String column, String like, {String? jsonObject}) async {
    var part = '';
    if (jsonObject != null) part = '"$jsonObject":"';
    final safeColumn = _safeColumn(column);
    final likeQuery = '%$part$like%';

    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName
      WHERE 1=1
        AND $safeColumn LIKE ?
      ORDER BY release_date DESC
    ''', [likeQuery]);

    return _toVideos(maps);
  }

  static Future<List<Videos>> getAllVideoPath(String column, String like) async {
    final safeColumn = _safeColumn(column);
    final normalizedLike = like.endsWith('%') ? like : '$like%';
    final basePath = normalizedLike.endsWith('%') ? normalizedLike.substring(0, normalizedLike.length - 1) : normalizedLike;
    final nestedPrefix = '$basePath/%/%';

    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName
      WHERE 1=1
        AND $safeColumn LIKE ? 
        AND $safeColumn NOT LIKE ?
      ORDER BY video_code ASC, title ASC
    ''', [normalizedLike, nestedPrefix]);

    return _toVideos(maps);
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
    return _toVideos(maps);
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
    return _toVideos(maps);
  }

  static Future<List<Videos>> getByActress(String actressName) async {
    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName WHERE json_extract(actress, '\$[0].name_romaji') LIKE ?
    ''', ['%$actressName%']);
    return _toVideos(maps);
  }

  // ** end get_by

  static Future<int> getCount() async {
    final maps = await _db.rawQuery('SELECT COUNT(*) AS total FROM $_tableName');
    return maps.isNotEmpty ? (maps.first['total'] as int? ?? 0) : 0;
  }

  static Future<void> updateViewCount(Videos video) async {
    final upd = video;
    upd.viewCount = (video.viewCount ?? 0) + 1;
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

  static String _normalizeDuplicateName(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    normalized = p.basenameWithoutExtension(normalized);
    normalized = normalized
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\([^\)]*\)'), ' ')
        .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\b(2160p|1080p|720p|540p|480p|360p|4k|8k|x264|x265|h264|h265|hevc|avc|aac|dts|hdr|uhd|fhd|webdl|webrip|brrip|bluray|remux|proper|repack|subindo|subtitle|subs|dubbed)\b'), ' ')
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized;
  }

  static String? _duplicateKeyForVideo(Videos video) {
    final code = (video.videoCode ?? '').trim().toLowerCase();
    if (code.isNotEmpty) return 'code:$code';

    final size = (video.filesize ?? 0).toInt();
    if (size <= 0) return null;

    final fileName = _normalizeDuplicateName(video.videoPath ?? '');
    if (fileName.isNotEmpty && fileName.length >= 4) {
      return 'name_size:$size:$fileName';
    }

    final title = _normalizeDuplicateName(video.title ?? '');
    if (title.isNotEmpty && title.length >= 4) {
      return 'title_size:$size:$title';
    }

    return null;
  }

  static String? _probableDuplicateKeyForVideo(Videos video) {
    final code = (video.videoCode ?? '').trim().toLowerCase();
    if (code.isNotEmpty) return 'code:$code';

    final fileName = _normalizeDuplicateName(video.videoPath ?? '');
    if (fileName.isNotEmpty && fileName.length >= 6) {
      return 'name:$fileName';
    }

    final title = _normalizeDuplicateName(video.title ?? '');
    if (title.isNotEmpty && title.length >= 6) {
      return 'title:$title';
    }

    return null;
  }

  static bool _isProbableDuplicatePair(Videos a, Videos b) {
    final durationA = (a.duration ?? 0).toInt();
    final durationB = (b.duration ?? 0).toInt();
    if (durationA > 0 && durationB > 0) {
      final diff = (durationA - durationB).abs();
      if (diff <= 180) return true;
      return false;
    }

    final sizeA = (a.filesize ?? 0).toDouble();
    final sizeB = (b.filesize ?? 0).toDouble();
    if (sizeA > 0 && sizeB > 0) {
      final minSize = sizeA < sizeB ? sizeA : sizeB;
      final maxSize = sizeA > sizeB ? sizeA : sizeB;
      if (maxSize <= 0) return false;

      final ratio = minSize / maxSize;
      return ratio >= 0.45;
    }

    return false;
  }

  static List<Videos> _filterProbableDuplicateGroup(List<Videos> items) {
    if (items.length <= 1) return [];

    final matchedIndexes = <int>{};
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        if (_isProbableDuplicatePair(items[i], items[j])) {
          matchedIndexes.add(i);
          matchedIndexes.add(j);
        }
      }
    }

    if (matchedIndexes.length <= 1) return [];
    final indexes = matchedIndexes.toList()..sort();
    return indexes.map((index) => items[index]).toList();
  }

  static Future<List<List<Videos>>> getDuplicateVideoGroups({String mode = 'exact'}) async {
    final videos = await getAll(orderBy: 'video_code ASC, title ASC, video_path ASC');
    final grouped = <String, List<Videos>>{};

    for (final video in videos) {
      final key = mode == 'probable'
          ? _probableDuplicateKeyForVideo(video)
          : _duplicateKeyForVideo(video);
      if (key == null) continue;
      grouped.putIfAbsent(key, () => <Videos>[]).add(video);
    }

    final duplicates = <List<Videos>>[];
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final aType = a.startsWith('code:') ? 0 : 1;
        final bType = b.startsWith('code:') ? 0 : 1;
        if (aType != bType) return aType.compareTo(bType);
        return a.compareTo(b);
      });

    for (final key in keys) {
      final items = grouped[key] ?? [];
      if (items.length <= 1) continue;

      items.sort((a, b) {
        final aPath = (a.videoPath ?? '').toLowerCase();
        final bPath = (b.videoPath ?? '').toLowerCase();
        return aPath.compareTo(bPath);
      });

      if (mode == 'probable' && key.startsWith('code:') == false) {
        final probableItems = _filterProbableDuplicateGroup(items);
        if (probableItems.length > 1) duplicates.add(probableItems);
        continue;
      }

      duplicates.add(items);
    }

    return duplicates;
  }

  static Future<List<Videos>> getListDuplicateVideos({String mode = 'exact'}) async {
    final groups = await getDuplicateVideoGroups(mode: mode);
    return groups.expand((items) => items).toList();
  }

  static Future<num?> getTotalFileSizeAllVideo() async {
    final maps = await _db.rawQuery('SELECT sum(filesize) as total FROM videos');
    return maps.first['total'] as num?;
  }
}
