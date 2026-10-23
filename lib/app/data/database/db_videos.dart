import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../core/const.dart';
import '../../utils/helper.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';

mixin DBVideos {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'videos';
  static final revision = 0.obs;
  static int viewCountRevision = 0;
  static const _metadataColumns = {
    'video_code', 'title', 'title_ja', 'description', 'fan_art', 'poster', 'trailer',
    'actress', 'category', 'release_date', 'release_date_formated',
    'duration', 'duration_formated', 'studio', 'label', 'director',
    'series', 'screenshot', 'site',
  };
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

  static List<Videos> _toVideos(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<void> addBulk(List<Videos> videos, {DatabaseExecutor? executor}) async {
    Future<void> insert(DatabaseExecutor db) async {
      for (final video in videos) {
        if ((video.videoPath ?? '').trim().isEmpty || (video.rootPath ?? '').trim().isEmpty) {
          throw ArgumentError('Video path and root are required');
        }
        video.id = const UuidV4().generate();
        video.createdAt = video.updatedAt = DateTime.now().toStringEx();
        video.viewCount ??= 0;
        video.isFavorite ??= 0;
        video.duration ??= 0;
        video.filesize ??= 0;
        _normalizeMetadata(video);
        final values = video.toJson();
        await db.rawInsert('''
          INSERT INTO videos (${values.keys.join(', ')}) VALUES (${List.filled(values.length, '?').join(', ')})
          ON CONFLICT(video_path) DO NOTHING
        ''', values.values.toList());
      }
    }
    if (executor != null) {
      await insert(executor);
    } else {
      await _db.transaction(insert);
    }
  }

  static void _normalizeMetadata(Videos video) {
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
        final actress = video.actress![j];
        var name = (actress.nameRomaji ?? '').trim();
        if (!_hasMetadataValue(name)) {
          name = '';
          if (!_hasMetadataValue(actress.nameKana) && !_hasMetadataValue(actress.nameKanji)
              && _hasMetadataValue(actress.imageUrl)) {
            final image = actress.imageUrl!.trim();
            name = p.basenameWithoutExtension(Uri.tryParse(image)?.path ?? image);
          }
        }
        actress.nameRomaji = HelperMisc.formatActressName(name);
      }
    }
  }

  static bool _hasMetadataValue(Object? value) => value != null
      && (value is! String || value.trim().isNotEmpty && value.trim().toLowerCase() != 'null');

  static Future<int> updateMetadata(Videos video, Videos metadata, {bool notify = true}) async {
    metadata.actress = metadata.actress?.where((actress) => _hasMetadataValue(actress.nameRomaji)
        || _hasMetadataValue(actress.nameKana) || _hasMetadataValue(actress.nameKanji)
        || _hasMetadataValue(actress.imageUrl)).toList();
    metadata.category = metadata.category?.where((category) => _hasMetadataValue(category.category)).toList();
    metadata.screenshot = metadata.screenshot?.where(_hasMetadataValue).toList();
    _normalizeMetadata(metadata);
    final values = metadata.toJson()..removeWhere((key, value) => !_metadataColumns.contains(key)
        || !_hasMetadataValue(value) || value == '[]');
    if ((metadata.duration ?? 0) <= 0) {
      values.remove('duration');
      values.remove('duration_formated');
    } else {
      values['duration_formated'] = HelperMisc.durationFormatDB(metadata.duration!);
    }
    if (!values.containsKey('release_date')) {
      values.remove('release_date_formated');
    } else {
      final date = DateFormat(kYMd).parseStrict(values['release_date']);
      values['release_date_formated'] = DateFormat(kMdY).format(date);
    }
    if (values.isEmpty) return 0;
    values['updated_at'] = DateTime.now().toStringEx();
    final snapshot = video.toJson();
    final changed = await _db.transaction((txn) async {
      final rows = await txn.query(_tableName,
        where: 'id = ? AND video_path = ? AND is_deleted = 0', whereArgs: [video.id, video.videoPath]);
      if (rows.isEmpty) return 0;
      final current = Videos.fromJson(rows.single).toJson();
      if (_metadataColumns.any((column) => current[column] != snapshot[column])) return 0;
      return txn.update(_tableName, values,
        where: 'id = ? AND video_path = ? AND is_deleted = 0', whereArgs: [video.id, video.videoPath]);
    });
    if (changed > 0 && notify) revision.value++;
    return changed;
  }

  static Future<void> update(Videos videos, {Videos? original}) async {
    videos.updatedAt = DateTime.now().toStringEx();
    final values = videos.toJson()..removeWhere((key, value) => !_metadataColumns.contains(key)
      || key == 'duration' && value == null);
    values['updated_at'] = videos.updatedAt;
    final changed = original == null
        ? await _db.update(_tableName, values, where: 'id = ? AND is_deleted = 0', whereArgs: [videos.id])
        : await _db.transaction((txn) async {
            final rows = await txn.query(_tableName,
              where: 'id = ? AND video_path = ? AND is_deleted = 0', whereArgs: [original.id, original.videoPath]);
            final snapshot = original.toJson();
            final current = rows.isEmpty ? null : Videos.fromJson(rows.single).toJson();
            if (current == null || original.id != videos.id
                || _metadataColumns.any((column) => current[column] != snapshot[column])) {
              throw StateError('Video changed or was removed. Reopen it and try again.');
            }
            return txn.update(_tableName, values, where: 'id = ? AND is_deleted = 0', whereArgs: [videos.id]);
          });
    if (changed == 0) throw StateError('Video no longer exists');
    revision.value++;
  }

  static const _missingQuality = "is_deleted = 0 AND (quality IS NULL OR TRIM(quality) = '')";

  static Future<int> countMissingQuality() async => Sqflite.firstIntValue(
    await _db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE $_missingQuality'),
  ) ?? 0;

  static Future<List<Videos>> getMissingQuality() async => _toVideos(await _db.query(
    _tableName, columns: ['id', 'video_path'], where: _missingQuality,
  ));

  static Future<int> updateMissingQuality(Videos video, String quality) => _db.update(
    _tableName, {'quality': quality, 'updated_at': DateTime.now().toStringEx()},
    where: 'id = ? AND video_path = ? AND $_missingQuality', whereArgs: [video.id, video.videoPath],
  );

  static Future<int> recoverMissingVideoCodes(String rootPath) async {
    if (rootPath.isEmpty) return 0;
    return _db.transaction((txn) async {
      const missingCode = "(video_code IS NULL OR TRIM(video_code) = '')";
      final rows = await txn.query(_tableName, columns: ['id', 'video_path'], where: 'root_path = ? AND is_deleted = 0 AND $missingCode', whereArgs: [rootPath]);
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
    final changed = await _db.update(_tableName,
      {'is_deleted': 1, 'updated_at': DateTime.now().toStringEx()},
      where: 'id = ? AND is_deleted = 0', whereArgs: [videos.id]);
    if (changed > 0) revision.value++;
  }

  static Future<int> restore(Videos video) async {
    final changed = await _db.update(_tableName,
      {'is_deleted': 0, 'updated_at': DateTime.now().toStringEx()},
      where: 'id = ? AND is_deleted = 1', whereArgs: [video.id]);
    if (changed > 0) revision.value++;
    return changed;
  }

  static Future<int> deletePermanently(Videos video) async {
    final changed = await _db.delete(_tableName,
      where: 'id = ? AND is_deleted = 1', whereArgs: [video.id]);
    if (changed > 0) revision.value++;
    return changed;
  }

  static Future<int> deleteAllDeleted() async {
    final changed = await _db.delete(_tableName, where: 'is_deleted = 1');
    if (changed > 0) revision.value++;
    return changed;
  }

  static Future<void> deleteByVideoPaths(List<String> videoPaths, {DatabaseExecutor? executor}) async {
    if (videoPaths.isEmpty) return;
    final unique = videoPaths.where((p) => p.trim().isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;

    // Keep below SQLite variable limit.
    const chunkSize = 800;
    Future<void> remove(DatabaseExecutor txn) async {
      for (var i = 0; i < unique.length; i += chunkSize) {
        final chunk = unique.sublist(i, i + chunkSize > unique.length ? unique.length : i + chunkSize);
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.rawDelete(
          'DELETE FROM $_tableName WHERE is_deleted = 0 AND video_path IN ($placeholders)',
          chunk,
        );
      }
    }
    if (executor != null) {
      await remove(executor);
    } else {
      await _db.transaction(remove);
    }
  }

  static Future<void> deleteByRootPath(String rootPath) async {
    await _db.delete(_tableName, where: 'root_path = ?', whereArgs: [rootPath]);
  }

  static Future<int> moveVideoPaths(List<Map<String, String>> moves, {DatabaseExecutor? executor}) async {
    if (moves.isEmpty) return 0;
    var updatedRows = 0;
    final now = DateTime.now().toStringEx();

    Future<void> move(DatabaseExecutor txn) async {
      for (final move in moves) {
        final oldPath = move['oldPath'] ?? '';
        final newPath = move['newPath'] ?? '';
        final newRoot = move['newRoot'] ?? '';
        if (oldPath.trim().isEmpty || newPath.trim().isEmpty || newRoot.trim().isEmpty) continue;

        if (move['id'] != null) {
          final source = await txn.query(_tableName, where: 'id = ? AND video_path = ?', whereArgs: [move['id'], oldPath]);
          if (source.length != 1) throw StateError('The source changed during the library scan');
          final target = await txn.query(_tableName, where: 'video_path = ?', whereArgs: [newPath]);
          if (target.isNotEmpty) {
            final destination = target.single;
            if (destination['id'] != move['destinationId']) throw StateError('The destination changed during the library scan');
            final sourceId = source.single['id'];
            final targetId = destination['id'];
            await txn.rawInsert('''
              INSERT INTO playlist_item(playlist_id, video_id, created_at)
              SELECT playlist_id, ?, created_at FROM playlist_item WHERE video_id = ?
              ON CONFLICT(playlist_id, video_id) DO NOTHING
            ''', [sourceId, targetId]);
            await txn.update('watch_session', {'video_id': sourceId}, where: 'video_id = ?', whereArgs: [targetId]);
            await txn.rawUpdate('''
              UPDATE videos SET view_count = view_count + ?, is_favorite = MAX(is_favorite, ?),
                is_deleted = MAX(is_deleted, ?) WHERE id = ?
            ''', [destination['view_count'], destination['is_favorite'], destination['is_deleted'], sourceId]);
            await txn.delete(_tableName, where: 'id = ?', whereArgs: [targetId]);
          } else if (move['destinationId'] != null) {
            throw StateError('The destination changed during the library scan');
          }
        }

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
    }
    if (executor != null) {
      await move(executor);
    } else {
      await _db.transaction(move);
    }

    return updatedRows;
  }

  static Future<List<Videos>> getAll({String? where, List<Object?>? whereArgs, String? orderBy, String? groupBy, int? limit, bool includeDeleted = false}) async {
    final condition = includeDeleted ? where : 'is_deleted = 0${where == null ? '' : ' AND ($where)'}';
    final maps = await _db.query(_tableName, where: condition, whereArgs: whereArgs, groupBy: groupBy, orderBy: orderBy, limit: limit);
    return _toVideos(maps);
  }

  static Future<List<({Videos video, double weight})>> getRecommendationSeeds() async {
    final rows = await _db.rawQuery('''
      SELECT v.*, w.seconds, w.last_watched FROM videos v
      LEFT JOIN (
        SELECT video_id, SUM(watched_seconds) AS seconds, MAX(created_at) AS last_watched
        FROM watch_session WHERE video_id IS NOT NULL GROUP BY video_id
      ) w ON w.video_id = v.id
      WHERE v.is_deleted = 0 AND (v.is_favorite = 1 OR v.view_count > 0 OR w.seconds > 0)
    ''');
    final now = DateTime.now();
    return rows.map((row) {
      final video = Videos.fromJson(row);
      final seconds = (row['seconds'] as num?)?.toDouble();
      final lastWatched = DateTime.tryParse('${row['last_watched'] ?? ''}');
      final days = lastWatched == null ? 0 : math.max(0, now.difference(lastWatched).inDays);
      // Legacy opens are weak evidence; short recorded previews are not preferences.
      final watchedWeight = seconds == null
          ? math.log(1 + (video.viewCount ?? 0).clamp(0, 10)) * 0.15
          : seconds < 120 ? 0.0 : (seconds / 600).clamp(1.0, 3.0) * 30 / (30 + days);
      return (video: video, weight: (video.isFavorite == 1 ? 5.0 : 0.0) + watchedWeight);
    }).where((item) => item.weight > 0).toList();
  }

  static Future<List<Videos>> getAllLike(String column, String like, {String? jsonObject}) async {
    if (column == 'actress' || column == 'category') {
      final field = column == 'actress' ? 'id' : 'category';
      final maps = await _db.rawQuery('''
        SELECT * FROM videos v WHERE v.is_deleted = 0 AND EXISTS (
          SELECT 1 FROM json_each(v.$column) j WHERE CAST(json_extract(j.value, '\$.$field') AS TEXT) = ?
        ) ORDER BY release_date DESC
      ''', [like]);
      return _toVideos(maps);
    }
    var part = '';
    if (jsonObject != null) part = '"$jsonObject":"';
    final safeColumn = _safeColumn(column);
    final likeQuery = '%$part$like%';

    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName
      WHERE is_deleted = 0
        AND $safeColumn LIKE ?
      ORDER BY release_date DESC
    ''', [likeQuery]);

    return _toVideos(maps);
  }

  static Future<List<Videos>> getAllVideoPath(String column, String like) async {
    final safeColumn = _safeColumn(column);
    final basePath = p.normalize(like);
    final directory = basePath.endsWith(p.separator) ? basePath : '$basePath${p.separator}';
    final escaped = directory.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final normalizedLike = '$escaped%';
    final nestedPrefix = '$escaped%${p.separator == '\\' ? '\\\\' : p.separator}%';

    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName
      WHERE is_deleted = 0
        AND $safeColumn LIKE ? ESCAPE '\\'
        AND $safeColumn NOT LIKE ? ESCAPE '\\'
      ORDER BY video_code ASC, title ASC
    ''', [normalizedLike, nestedPrefix]);

    return _toVideos(maps);
  }

  static Future<List<Videos>> search(String s) async {
    final query = '%$s%';
    final maps = await _db.rawQuery('''
      SELECT * FROM $_tableName 
      WHERE is_deleted = 0
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
    final maps = await _db.query(_tableName, where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return Videos.fromJson(maps.first);
  }

  static Future<Videos> getByCode(String code) async {
    final maps = await _db.query(_tableName, where: 'video_code = ? AND is_deleted = 0', whereArgs: [code]);
    return Videos.fromJson(maps.first);
  }

  static Future<Videos?> getByVideoPath(String videoPath) async {
    var maps = await _db.query(_tableName, where: 'video_path = ? AND is_deleted = 0', whereArgs: [videoPath]);
    if (maps.isEmpty && Platform.isWindows) {
      maps = await _db.query(_tableName, where: 'video_path = ? COLLATE NOCASE AND is_deleted = 0', whereArgs: [videoPath], limit: 1);
    }
    return maps.isNotEmpty ? Videos.fromJson(maps.first) : null;
  }

  static Future<List<Videos>> getBySeries(String series) async {
    final maps = await _db.query(_tableName, where: 'series = ? AND is_deleted = 0', whereArgs: [series]);
    return _toVideos(maps);
  }

  static Future<List<Videos>> getByActress(String actressName) async {
    final maps = await _db.rawQuery('''
      SELECT * FROM videos v WHERE v.is_deleted = 0 AND EXISTS (
        SELECT 1 FROM json_each(v.actress) j WHERE json_extract(j.value, '\$.name_romaji') = ? COLLATE NOCASE
      )
    ''', [actressName]);
    return _toVideos(maps);
  }

  // ** end get_by

  static Future<int> getCount() async {
    final maps = await _db.rawQuery('SELECT COUNT(*) AS total FROM $_tableName WHERE is_deleted = 0');
    return maps.isNotEmpty ? (maps.first['total'] as int? ?? 0) : 0;
  }

  static Future<void> updateViewCount(Videos video) async {
    var updated = false;
    await _db.transaction((txn) async {
      final changed = await txn.rawUpdate('UPDATE videos SET view_count = view_count + 1 WHERE id = ? AND is_deleted = 0', [video.id]);
      if (changed == 0) return;
      final rows = await txn.query('videos', columns: ['view_count'], where: 'id = ? AND is_deleted = 0', whereArgs: [video.id], limit: 1);
      video.viewCount = rows.single['view_count'] as int;
      updated = true;
    });
    if (updated) viewCountRevision++;
  }

  static Future<void> _setFavorite(Videos video, int favorite) async {
    final now = DateTime.now().toStringEx();
    final changed = await _db.update('videos', {'is_favorite': favorite, 'updated_at': now}, where: 'id = ? AND is_deleted = 0', whereArgs: [video.id]);
    if (changed == 0) return;
    video.isFavorite = favorite;
    video.updatedAt = now;
    revision.value++;
  }

  static Future<void> addToFavorite(Videos video) => _setFavorite(video, 1);

  static Future<void> removeFromFavorite(Videos video) => _setFavorite(video, 0);

  // ────────────────────────────────────────────────────────────────
  // ⵌ helper
  static Future<void> deleteAll() async => await _db.delete(_tableName);
  // Category ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllCategoryWithCount() async {
    final categoryIdToCount = {};
    final uniqueCategory = {};

    final rawData = await _db.rawQuery('SELECT category FROM $_tableName WHERE is_deleted = 0');

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

    final rawData = await _db.rawQuery('SELECT actress FROM $_tableName WHERE is_deleted = 0');

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
      WHERE is_deleted = 0
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
      WHERE is_deleted = 0
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
      WHERE is_deleted = 0
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
      WHERE is_deleted = 0
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
    final rawData = await _db.rawQuery('SELECT video_path FROM $_tableName WHERE is_deleted = 0');
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
      WHERE is_deleted = 0
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

  static String _normalizeDuplicateName(String value, {bool filePath = false}) {
    var normalized = value.trim().toLowerCase();
    if (filePath) normalized = p.basenameWithoutExtension(normalized.replaceAll('\\', '/'));
    return normalized
        .replaceAll(RegExp(r'[_\-.\[\](){}/]+'), ' ')
        .replaceAll(RegExp(r'\b(2160p|1080p|720p|540p|480p|360p|4k|8k|x264|x265|h264|h265|hevc|avc|aac|dts|hdr|uhd|fhd|webdl|webrip|brrip|bluray|remux|proper|repack|subindo|subtitle|subs|dubbed)\b'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isProbableDuplicatePair(Videos a, Videos b) {
    final durationA = (a.duration ?? 0).toDouble();
    final durationB = (b.duration ?? 0).toDouble();
    if (durationA > 0 && durationB > 0) {
      final tolerance = math.max(3, math.min(durationA, durationB) * .03);
      return (durationA - durationB).abs() <= tolerance;
    }
    final sizeA = (a.filesize ?? 0).toDouble();
    final sizeB = (b.filesize ?? 0).toDouble();
    // ponytail: size-only fallback is a candidate heuristic; content hashes are needed to prove identical files.
    return sizeA > 0 && sizeB > 0 && math.min(sizeA, sizeB) / math.max(sizeA, sizeB) >= .45;
  }

  static Future<List<List<Videos>>> getDuplicateVideoGroups({String mode = 'exact'}) async {
    final videos = await getAll(orderBy: 'video_code ASC, title ASC, video_path ASC');
    final candidates = <String, List<int>>{};
    for (var index = 0; index < videos.length; index++) {
      final video = videos[index];
      final code = (video.videoCode ?? '').trim().toLowerCase();
      if (code.isNotEmpty) {
        candidates.putIfAbsent('code:$code', () => []).add(index);
        continue;
      }
      final size = (video.filesize ?? 0).toInt();
      if (mode != 'probable' && size <= 0) continue;
      final names = {
        _normalizeDuplicateName(video.videoPath ?? '', filePath: true),
        _normalizeDuplicateName(video.title ?? ''),
      };
      for (final name in names.where((name) => name.length >= 4)) {
        final key = mode == 'probable' ? 'name:$name' : 'name:$size:$name';
        candidates.putIfAbsent(key, () => []).add(index);
      }
    }

    final parents = List.generate(videos.length, (index) => index);
    int root(int index) {
      while (parents[index] != index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    }
    for (final entry in candidates.entries) {
      final indexes = entry.value;
      if (entry.key.startsWith('code:') || mode != 'probable') {
        for (final index in indexes.skip(1)) parents[root(index)] = root(indexes.first);
      } else {
        for (var i = 0; i < indexes.length; i++) {
          for (var j = i + 1; j < indexes.length; j++) {
            if (_isProbableDuplicatePair(videos[indexes[i]], videos[indexes[j]])) {
              parents[root(indexes[j])] = root(indexes[i]);
            }
          }
        }
      }
    }
    final groups = <int, List<Videos>>{};
    for (var index = 0; index < videos.length; index++) {
      groups.putIfAbsent(root(index), () => []).add(videos[index]);
    }
    return groups.values.where((items) => items.length > 1).map((items) {
      items.sort((a, b) => (a.videoPath ?? '').compareTo(b.videoPath ?? ''));
      return items;
    }).toList();
  }

  static Future<List<Videos>> getListDuplicateVideos({String mode = 'exact'}) async {
    final groups = await getDuplicateVideoGroups(mode: mode);
    return groups.expand((items) => items).toList();
  }

  static Future<num?> getTotalFileSizeAllVideo() async {
    final maps = await _db.rawQuery('SELECT sum(filesize) as total FROM videos WHERE is_deleted = 0');
    return maps.first['total'] as num?;
  }
}
