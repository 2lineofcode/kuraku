import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';

import '../models/videos_entity.dart';
import 'db_init.dart';

mixin DBVideos {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'Videos';

  static Future<bool> _validation(Videos videos) async {
    final isDuplicateVideoPath = await getByVideoPath(videos.videoPath ?? '');
    if (isDuplicateVideoPath.isNotEmpty) return false;

    // final isDuplicateVideoCode = await getByCode(videos.videoCode ?? '');
    // if (isDuplicateVideoCode.isNotEmpty) return false;

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

  static Future<List<Videos>> search(String s) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
      SELECT * FROM $_tableName 
      WHERE 1=1
        AND video_code LIKE '%$s%'
        OR title LIKE '%$s%'
    ''', [s]);
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

  static Future<void> updateViewCount(Videos video) async {
    final upd = video;
    upd.viewCount = video.viewCount! + 1;
    await _db.update(_tableName, upd.toJson(), where: 'id = ?', whereArgs: [video.id]);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ helper

  // Category ────────────────────────────────────────────────────────────────
  static Future<List<VideoCategory>> getAllCategories() async {
    final category = <VideoCategory>[];
    await getAll().then((video) {
      for (final item in video) {
        if (!item.category.isEmptyOrNull) {
          for (int i = 0; i < item.category!.length; i++) {
            category.add(item.category![i]);
          }
        }
      }
    });
    category.unique((e) => e.id);
    return category;
  }

  static Future<List<Videos>> getVideoByCategories(num catId) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (!item.category.isEmptyOrNull) {
          for (int i = 0; i < item.category!.length; i++) {
            if (item.category![i].id == catId) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }

  // Actress ────────────────────────────────────────────────────────────────
  static Future<List<VideoActress>> getAllActress() async {
    final actress = <VideoActress>[];
    await getAll().then((video) {
      for (final item in video) {
        if (!item.actress.isEmptyOrNull) {
          for (int i = 0; i < item.actress!.length; i++) {
            actress.add(item.actress![i]);
          }
        }
      }
    });
    actress.unique((e) => e.id);
    return actress;
  }

  static Future<List<Videos>> getVideoByActress(num actressId) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (!item.actress.isEmptyOrNull) {
          for (int i = 0; i < item.actress!.length; i++) {
            if (item.actress![i].id == actressId) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }

  // Studio ────────────────────────────────────────────────────────────────
  static Future<List<String>> getAllStudio() async {
    final studio = <String>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.studio.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.studio!.length; i++) {
            studio.add(item.studio!);
          }
        }
      }
    });
    studio.unique((e) => e);
    return studio;
  }

  static Future<List<Videos>> getVideoByStudio(String studio) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.studio.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.studio!.length; i++) {
            if (item.studio == studio) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }

  // Label ────────────────────────────────────────────────────────────────
  static Future<List<String>> getAllLabel() async {
    final label = <String>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.label.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.label!.length; i++) {
            label.add(item.label!);
          }
        }
      }
    });
    label.unique((e) => e);
    return label;
  }

  static Future<List<Videos>> getVideoByLabel(String label) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.label.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.label!.length; i++) {
            if (item.label == label) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }

  // Series ────────────────────────────────────────────────────────────────
  static Future<List<String>> getAllSeries() async {
    final series = <String>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.series.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.series!.length; i++) {
            series.add(item.series!);
          }
        }
      }
    });
    series.unique((e) => e);
    return series;
  }

  static Future<List<Videos>> getVideoBySeries(String series) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.series.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.series!.length; i++) {
            if (item.series == series) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }

  // Director ────────────────────────────────────────────────────────────────
  static Future<List<String>> getAllDirector() async {
    final director = <String>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.director.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.director!.length; i++) {
            director.add(item.director!);
          }
        }
      }
    });
    director.unique((e) => e);
    return director;
  }

  static Future<List<Videos>> getVideoByDirector(String director) async {
    final output = <Videos>[];
    await getAll().then((video) {
      for (final item in video) {
        if (item.director.isNotEmptyAndNotNull) {
          for (int i = 0; i < item.director!.length; i++) {
            if (item.director == director) output.add(item);
          }
        }
      }
    });
    output.unique((e) => e.videoPath);
    return output;
  }
}
