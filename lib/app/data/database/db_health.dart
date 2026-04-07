import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/const.dart';
import '_init_db.dart';
import 'db_videos.dart';

class HealthSummary {
  final int totalVideo;
  final int duplicatePaths;
  final int missingFiles;
  final int externalOffline;
  final int missingMetadata;
  final int watchSeconds7d;
  final int watchSeconds30d;

  HealthSummary({
    required this.totalVideo,
    required this.duplicatePaths,
    required this.missingFiles,
    required this.externalOffline,
    required this.missingMetadata,
    required this.watchSeconds7d,
    required this.watchSeconds30d,
  });
}

mixin DBHealth {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<int> _countDuplicatePaths() async {
    final maps = await _db.rawQuery('''
      SELECT COALESCE(SUM(cnt - 1), 0) AS total
      FROM (
        SELECT COUNT(*) AS cnt
        FROM videos
        WHERE video_path IS NOT NULL AND video_path != ''
        GROUP BY video_path
        HAVING COUNT(*) > 1
      ) x
    ''');
    return (maps.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<int> _countMissingMetadata() async {
    final maps = await _db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM videos
      WHERE
        title IS NULL OR title = ''
        OR release_date IS NULL OR release_date = ''
        OR fan_art IS NULL OR fan_art = ''
        OR actress IS NULL OR actress = ''
        OR category IS NULL OR category = ''
    ''');
    return (maps.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<int> _sumWatchSecondsSince(DateTime since) async {
    final maps = await _db.rawQuery('''
      SELECT COALESCE(SUM(watched_seconds), 0) AS total
      FROM watch_session
      WHERE created_at >= ?
    ''', [since.toStringEx()]);
    return (maps.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<HealthSummary> computeSummary() async {
    final allVideos = await DBVideos.getAll();
    final totalVideo = allVideos.length;

    var missingFiles = 0;
    var externalOffline = 0;
    for (final v in allVideos) {
      final path = v.videoPath ?? '';
      if (path.isEmpty) {
        missingFiles++;
        continue;
      }
      if (!File(path).existsSync()) {
        missingFiles++;
        if (path.startsWith('/Volumes/')) externalOffline++;
      }
    }

    final duplicatePaths = await _countDuplicatePaths();
    final missingMetadata = await _countMissingMetadata();
    final watchSeconds7d = await _sumWatchSecondsSince(DateTime.now().subtract(7.days));
    final watchSeconds30d = await _sumWatchSecondsSince(DateTime.now().subtract(30.days));

    return HealthSummary(
      totalVideo: totalVideo,
      duplicatePaths: duplicatePaths,
      missingFiles: missingFiles,
      externalOffline: externalOffline,
      missingMetadata: missingMetadata,
      watchSeconds7d: watchSeconds7d,
      watchSeconds30d: watchSeconds30d,
    );
  }

  static Future<void> saveSnapshot(HealthSummary summary) async {
    await _db.insert('health_snapshot', {
      'id': const UuidV4().generate(),
      'snapshot_date': DateTime.now().toStringEx(format: kYMd),
      'total_video': summary.totalVideo,
      'duplicate_paths': summary.duplicatePaths,
      'missing_files': summary.missingFiles,
      'external_offline': summary.externalOffline,
      'missing_metadata': summary.missingMetadata,
      'watch_seconds_7d': summary.watchSeconds7d,
      'watch_seconds_30d': summary.watchSeconds30d,
      'created_at': DateTime.now().toStringEx(),
    });
  }
}
