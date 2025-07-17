import 'package:get/get.dart';

import '../../models/videos_entity.dart';
import 'db_init.dart';

mixin DBVideos {
  static final _db = Get.find<DB>().dbMain;
  static final _tableName = 'Videos';

  static Future<bool> _validation(Videos videos) async {
    final checkRootFolder = await getByVideoPath(videos.videoCode ?? '');
    final checkCode = await getByCode(videos.videoCode ?? '');

    if (checkRootFolder.isNotEmpty) return false;
    if (checkCode.isNotEmpty) return false;

    return true;
  }

  static Future<void> add(Videos videos) async {
    final isOK = await _validation(videos);
    if (isOK) await _db.insert(_tableName, videos.toJson());
  }

  static Future<void> update(Videos videos) async {
    await _db.update(_tableName, videos.toJson(), where: 'id = ?', whereArgs: [videos.id]);
  }

  static Future<void> delete(Videos videos) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [videos.id]);
  }

  static Future<void> deleteByRootPath(String rootPath) async {
    await _db.delete(_tableName, where: 'root_path = ?', whereArgs: [rootPath]);
  }

  static Future<List<Videos>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> getByCode(String code) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'video_code = ?', whereArgs: [code]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<List<Videos>> getByVideoPath(String videoPath) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'video_path = ?', whereArgs: [videoPath]);
    return List.generate(maps.length, (index) => Videos.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }
}
