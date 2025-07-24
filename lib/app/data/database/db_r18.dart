import 'package:get/get.dart';

import 'db_init.dart';

mixin DBR18 {
  static final _db = Get.find<DBService>().dbR18;

  static Future<int> getCountAllVideos() async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('SELECT count(*) as total FROM derived_video');
    return maps[0]['total'] as int;
  }

  static Future<Map<String, dynamic>?> getVideo(String code) async {
    final maps = await _db.rawQuery('''
        SELECT
            v.content_id as id,                 -- id
            v.dvd_id as video_code,             -- video_code
            t.target_en as title,               -- title
            t.source_ja as title_ja,            -- title_ja
            s.name_en as series,                -- series
            m.name_ja as studio,                -- studio/maker
            l.name_en as label,                 -- label
            site.name as site,                  -- site
            v.runtime_mins as duration,         -- duration 
            v.release_date as release_date,     -- release_date
            v.sample_url as trailer,            -- trailer
            v.jacket_full_url as fan_art,       -- fanart
            v.jacket_thumb_url as poster,       -- poster
            v.gallery_full_first as ssfirst,    -- screenshot[0]
            v.gallery_full_last as sslast       -- screenshot[n]
        FROM
            derived_video v
            LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
            LEFT JOIN derived_maker m ON m.id = v.maker_id
            LEFT JOIN derived_series s ON s.id = v.series_id
            LEFT JOIN derived_label l ON l.id = v.label_id
            LEFT JOIN derived_site site ON site.id = v.site_id
        WHERE
            v.dvd_id = ?
        GROUP BY
            v.dvd_id
        ;
      ''', [code]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  static Future<List<Map<String, dynamic>>> getActress(String code) async {
    final maps = await _db.rawQuery('''
        SELECT DISTINCT a.*
        FROM derived_video_actress va
        JOIN derived_video v ON v.content_id = va.content_id
        JOIN derived_actress a ON a.id = va.actress_id
        WHERE v.dvd_id = ?;
      ''', [code]);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getCategory(String code) async {
    final maps = await _db.rawQuery('''
        SELECT DISTINCT  cat.id, cat.name_en as category
        FROM derived_video_category c 
        JOIN derived_video v ON v.content_id = c.content_id
        JOIN derived_category cat ON cat.id = c.category_id
        WHERE v.dvd_id = ? AND cat.name_en NOT NULL;
      ''', [code]);

    return maps;
  }

  static Future<Map<String, dynamic>?> getDirector(String code) async {
    final maps = await _db.rawQuery('''
        SELECT DISTINCT d.*
        FROM derived_video_director vd
        JOIN derived_video v ON v.content_id = vd.content_id
        JOIN derived_director d ON d.id = vd.director_id
        WHERE v.dvd_id = ?;
      ''', [code]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Actress
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByActress(int actressId) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) as total 
      FROM derived_video_actress 
      WHERE actress_id = '$actressId';
    ''');
    return maps[0]['total'] as int;
  }

  // TODO: FIX ME
  static Future<List<Map<String, dynamic>>> getAllVideosByActress(int actressId) async {
    final q1 = await _db.query('derived_video_actress', columns: ['content_id'], where: 'actress_id = ?', whereArgs: [actressId]);
    final listContentId = q1.map((row) => row['content_id'] as String).toList();

    if (listContentId.isEmpty) return [];

    final inClause = List.generate(listContentId.length, (index) => '?').join(', ');
    final q2 = await _db.rawQuery('''
      SELECT
          v.content_id as id,                 -- id
          v.dvd_id as video_code,             -- video_code
          v.release_date as release_date,     -- release_date
          v.jacket_full_url as fan_art,       -- fanart
          v.jacket_thumb_url as poster        -- poster
      FROM
          derived_video v
      WHERE 1=1
        AND v.dvd_id IS NOT NULL
        AND v.content_id IN ($inClause);
    ''', listContentId);
    return q2;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Category
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByCategory(String categoryName) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video_category vc 
      JOIN derived_category c ON c.id = vc.category_id
      WHERE c.name_en = ?;
    ''', [categoryName]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByCategory(String categoryName) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        JOIN derived_video_category vc ON vc.content_id = v.content_id
        JOIN derived_category c ON c.id = vc.category_id
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND c.name_en = ?;
      ''', [categoryName]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Label
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByLabel(String labelName) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video v
      JOIN derived_label l ON l.id = v.label_id
      WHERE l.name_en = ?;
    ''', [labelName]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByLabel(String labelName) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        JOIN derived_label l ON l.id = v.label_id
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND l.name_en = ?;
      ''', [labelName]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Series
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosBySeries(String series) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video v
      JOIN derived_series s ON s.id = v.series_id
      WHERE s.name_en LIKE ?;
    ''', [series]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosBySeries(String series) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          s.name_en AS series,
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        JOIN derived_series s ON s.id = v.series_id
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND s.name_en = ?;
      ''', [series]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Maker / Studio
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByStudio(String studio) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video v
      JOIN derived_maker m ON m.id = v.maker_id
      WHERE m.name_en = ? OR m.name_ja = ?;
    ''', [studio, studio]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByStudio(String studio) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        JOIN derived_maker m ON m.id = v.maker_id
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND m.name_en = ?;
      ''', [studio]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Director
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByDirector(String director) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video_director vd
      JOIN derived_director d ON d.id = vd.director_id
      WHERE d.name_romaji = ? OR d.name_kana = ?;
    ''', [director, director]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByDirector(String director) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        JOIN derived_video_director vd ON vd.content_id = v.content_id
        JOIN derived_director d ON d.id = vd.director_id
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND d.name_romaji = ? OR d.name_kana = ?;
      ''', [director, director]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Year
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByYear(String year) async {
    final maps = await _db.rawQuery('''
      SELECT count(*) AS total
      FROM derived_video v 
      WHERE v.release_date LIKE ?
    ''', ['$year%']);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByYear(String year) async {
    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,
          v.dvd_id AS video_code, 
          v.release_date AS release_date, 
          v.jacket_full_url AS fan_art,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        WHERE 1=1
          AND v.dvd_id IS NOT NULL
          AND v.release_date LIKE ?
      ''', ['$year%']);
    return maps;
  }
}
