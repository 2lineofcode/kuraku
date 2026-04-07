import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/videos_entity.dart';
import '_init_db.dart';

mixin DBWatchSession {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> addSession({
    required Videos video,
    required Duration duration,
  }) async {
    if (duration.inSeconds <= 0) return;

    await _db.insert('watch_session', {
      'id': const UuidV4().generate(),
      'video_id': video.id ?? '',
      'video_code': video.videoCode ?? '',
      'watched_seconds': duration.inSeconds,
      'created_at': DateTime.now().toStringEx(),
    });
  }
}
