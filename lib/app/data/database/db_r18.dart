import 'package:get/get.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import '../../core/app_setting.dart';
import '_init_db.dart';

mixin DBR18 {
  static final _db = Get.find<DBService>().dbR18;

  static Future<bool> _validation() async {
    var files = Glob('r18*.db').listSync(root: Get.find<AppSettingService>().appPath);
    files.sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) return false;

    if (await files[0].exists()) return true;
    return false;
  }

  static Future<int> getCountAllVideos() async {
    if (await _validation() == false) return 0;

    final List<Map<String, dynamic>> maps = await _db.rawQuery('SELECT count(*) as total FROM derived_video');
    return maps[0]['total'] as int;
  }

  static Future<Map<String, dynamic>?> getVideo(String code) async {
    if (await _validation() == false) return null;

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id as id,                                         -- id
          v.dvd_id as video_code,                                     -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,     -- title
          v.title_ja,                                                 -- title_ja
          s.name_en as series,                                        -- series
          COALESCE(m.name_en, m.name_ja) AS studio,                   -- studio/maker
          l.name_en as label,                                         -- label
          site.name as site,                                          -- site
          v.runtime_mins as duration,                                 -- duration 
          v.release_date as release_date,                             -- release_date
          v.sample_url as trailer,                                    -- trailer
          v.jacket_full_url as fan_art,                               -- fanart
          v.jacket_thumb_url as poster,                               -- poster
          v.gallery_full_first as ssfirst,                            -- screenshot[0]
          v.gallery_full_last as sslast                               -- screenshot[n]
        FROM
          derived_video v
          LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
          LEFT JOIN derived_maker m ON m.id = v.maker_id
          LEFT JOIN derived_series s ON s.id = v.series_id
          LEFT JOIN derived_label l ON l.id = v.label_id
          LEFT JOIN derived_site site ON site.id = v.site_id
        WHERE 1=1
          AND v.dvd_id = ?
      ''', [code]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  static Future<List<Map<String, dynamic>>> search(String query, {int? limit = 5000}) async {
    if (await _validation() == false) return [];

    final searchString = '%$query%';

    final subQuery = '''
    (
      SELECT v2.dvd_id FROM derived_video v2 
      WHERE 
        v2.dvd_id LIKE ? OR v2.title_en LIKE ?
      UNION
      SELECT v3.dvd_id FROM derived_video v3 
      JOIN machine_translation t2 ON t2.source_ja = v3.title_ja WHERE t2.target_en LIKE ?
    )
  ''';

    final maps = await _db.rawQuery('''
    SELECT
        v.content_id AS id,                                       -- id
        v.dvd_id AS video_code,                                   -- video_code
        COALESCE(t.target_en, v.title_en, v.title_ja) AS title,   -- title
        v.runtime_mins AS duration,                               -- duration
        v.release_date AS release_date,                           -- release_date
        v.sample_url AS trailer,                                  -- trailer
        v.jacket_full_url AS fan_art,                             -- fanart
        v.jacket_thumb_url AS poster,                             -- poster
        v.gallery_full_first AS ssfirst,                          -- screenshot[0]
        v.gallery_full_last AS sslast,                            -- screenshot[n]
        GROUP_CONCAT(dc.name_en, ', ') AS categories,             -- categories
        GROUP_CONCAT(da.name_romaji, ', ') AS actresses           -- actresses
    FROM derived_video v
    LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
    LEFT JOIN derived_video_category dvc ON dvc.content_id = v.content_id
    LEFT JOIN derived_category dc on dc.id = dvc.category_id
    LEFT JOIN derived_video_actress dva ON dva.content_id = v.content_id
    LEFT JOIN derived_actress da ON da.id = dva.actress_id
    WHERE
      v.dvd_id IS NOT NULL AND v.dvd_id IN $subQuery
      AND v.release_date IS NOT NULL
    GROUP BY v.dvd_id
    ORDER BY v.release_date DESC
    LIMIT ?
  ''', [searchString, searchString, searchString, limit]);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getAllActress({String? q}) async {
    if (await _validation() == false) return [];

    var whereClause = '''
    name_romaji IS NOT NULL
    AND name_romaji GLOB '[a-zA-Z]*'
    AND name_romaji NOT GLOB '*[0-9]*'
    AND name_romaji NOT GLOB '*[(-)]*'
    AND name_romaji NOT GLOB '*[!@#\$%%^&*()_-+=~`{}|:;"<>?,./]*'
    AND LENGTH(name_romaji) >= 3
  ''';
    var whereArgs = [];

    if (q != null) {
      whereClause += ' AND name_romaji LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _db.query(
      'derived_actress',
      columns: ['*', 'name_romaji AS name_en'],
      where: whereClause,
      whereArgs: whereArgs,
      groupBy: 'name_romaji',
      orderBy: 'name_romaji',
    );

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getActress(String code) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT DISTINCT 
          a.*
        FROM derived_video_actress va
        JOIN derived_video v ON v.content_id = va.content_id
        JOIN derived_actress a ON a.id = va.actress_id
        WHERE 1=1
          AND v.dvd_id = ?
      ''', [code]);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getAllSeries({String? q}) async {
    if (await _validation() == false) return [];

    var whereClause = 'name_en IS NOT NULL';
    var whereArgs = [];

    if (q != null) {
      whereClause += ' AND name_en LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _db.query(
      'derived_series',
      distinct: true,
      where: whereClause,
      whereArgs: whereArgs,
      groupBy: 'name_en',
      orderBy: 'name_en',
    );

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getAllCategories({String? q}) async {
    if (await _validation() == false) return [];

    var whereClause = 'name_en IS NOT NULL';
    var whereArgs = [];

    if (q != null) {
      whereClause += ' AND name_en LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _db.query(
      'derived_category',
      distinct: true,
      where: whereClause,
      whereArgs: whereArgs,
      groupBy: 'name_en',
      orderBy: 'name_en',
    );

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getCategory(String code) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT DISTINCT
          cat.id AS id, 
          cat.name_en AS category
        FROM derived_video_category c 
        JOIN derived_video v ON v.content_id = c.content_id
        JOIN derived_category cat ON cat.id = c.category_id
        WHERE 1=1
          AND v.dvd_id = ? 
          AND cat.name_en NOT NULL
      ''', [code]);

    return maps;
  }

  static Future<Map<String, dynamic>?> getDirector(String code) async {
    if (await _validation() == false) return null;

    final maps = await _db.rawQuery('''
        SELECT DISTINCT 
          d.*
        FROM derived_video_director vd
        JOIN derived_video v ON v.content_id = vd.content_id
        JOIN derived_director d ON d.id = vd.director_id
        WHERE 1=1
          AND v.dvd_id = ?
      ''', [code]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Actress
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByActress(int actressId) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT
        COUNT(da.id) AS total
      FROM
        derived_video v
        JOIN derived_video_actress dva ON dva.content_id = v.content_id
        JOIN derived_actress da ON da.id = dva.actress_id
      WHERE
        v.dvd_id IS NOT NULL
        AND da.id = ?
        AND EXISTS (
          SELECT 1 FROM derived_video_actress dva2
          WHERE dva2.content_id = v.content_id
          GROUP BY dva2.content_id
          HAVING COUNT(dva2.actress_id) = 1
        );
    ''', [actressId]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByActress(int actressId) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
      SELECT
        da.id AS actress_id,                                      -- actress_id
        v.content_id AS id,                                       -- id
        v.dvd_id AS video_code,                                   -- video_code
        COALESCE(t.target_en, v.title_en, v.title_ja) AS title,   -- title
        v.release_date AS release_date,                           -- release_date
        v.sample_url AS trailer,                                  -- trailer
        v.jacket_full_url AS fan_art,                             -- fan_art
        v.jacket_thumb_url AS poster                              -- poster
      FROM
        derived_video v
      JOIN derived_video_actress dva ON dva.content_id = v.content_id
      JOIN derived_actress da ON da.id = dva.actress_id
      LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
      WHERE 1=1
        AND v.dvd_id IS NOT NULL
        AND da.id = ?
        AND v.content_id IN (
          SELECT content_id
          FROM derived_video_actress
          GROUP BY content_id
          HAVING COUNT(actress_id) = 1
        )
      ORDER BY
        v.release_date DESC
      LIMIT 10000;
    ''', [actressId]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Category
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByCategory(String categoryName) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video_category vc 
      JOIN derived_category c ON c.id = vc.category_id
      WHERE 1=1
        AND c.name_en = ?
    ''', [categoryName]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByCategory(String categoryName) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,                                       -- id
          v.dvd_id AS video_code,                                   -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,   -- title
          v.release_date AS release_date,                           -- release_date
          v.sample_url AS trailer,                                  -- trailer
          v.jacket_full_url AS fan_art,                             -- fan_art
          v.jacket_thumb_url AS poster                              -- poster
        FROM derived_video v
        JOIN derived_video_category vc ON vc.content_id = v.content_id
        JOIN derived_category c ON c.id = vc.category_id
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND c.name_en = ?
          AND v.dvd_id IS NOT NULL
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', [categoryName]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Label
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByLabel(String labelName) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_label l ON l.id = v.label_id
      WHERE 1=1
        AND l.name_en = ?
        AND v.dvd_id IS NOT NULL
    ''', [labelName]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByLabel(String labelName) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
        v.content_id AS id,                                      -- id
        v.dvd_id AS video_code,                                  -- video_code
        COALESCE(t.target_en, v.title_en, v.title_ja) AS title,  -- title
        v.release_date AS release_date,                          -- release_date
        v.sample_url AS trailer,                                 -- trailer
        v.jacket_full_url AS fan_art,                            -- fan_art
        v.jacket_thumb_url AS poster                             -- poster
        FROM derived_video v
        JOIN derived_label l ON l.id = v.label_id
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND l.name_en = ?
          AND v.dvd_id IS NOT NULL
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', [labelName]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Series
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosBySeries(String series) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_series s ON s.id = v.series_id
      WHERE 1=1
        AND s.name_en LIKE ?
        AND v.dvd_id IS NOT NULL
    ''', [series]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosBySeries(String series) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,                                       -- id
          v.dvd_id AS video_code,                                   -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,   -- title
          s.name_en AS series,                                      -- series
          v.release_date AS release_date,                           -- release_date
          v.sample_url AS trailer,                                  -- trailer
          v.jacket_full_url AS fan_art,                             -- fan_art
          v.jacket_thumb_url AS poster                              -- poster
        FROM derived_video v
        LEFT JOIN derived_series s ON s.id = v.series_id
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND s.name_en = ?
          AND v.dvd_id IS NOT NULL
        GROUP BY
          v.dvd_id
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', [series]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Maker / Studio
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByStudio(String studio) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_maker m ON m.id = v.maker_id
      WHERE 1=1
        AND m.name_en = ? OR m.name_ja = ?
        AND v.dvd_id IS NOT NULL
    ''', [studio, studio]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByStudio(String studio) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,                                       -- id
          v.dvd_id AS video_code,                                   -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,   -- title
          v.release_date AS release_date,                           -- release_date
          v.sample_url AS trailer,                                  -- trailer
          v.jacket_full_url AS fan_art,                             -- fan_art
          v.jacket_thumb_url AS poster                              -- poster
        FROM derived_video v
        JOIN derived_maker m ON m.id = v.maker_id
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND m.name_en = ? OR m.name_ja = ?
          AND v.dvd_id IS NOT NULL
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', [studio, studio]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Director
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByDirector(String director) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video_director vd
      JOIN derived_director d ON d.id = vd.director_id
      WHERE 1=1
        AND d.name_romaji = ? OR d.name_kana = ?
    ''', [director, director]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByDirector(String director) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,                                         -- id
          v.dvd_id AS video_code,                                     -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,     -- title
          v.release_date AS release_date,                             -- release_date
          v.sample_url AS trailer,                                    -- trailer
          v.jacket_full_url AS fan_art,                               -- fan_art
          v.jacket_thumb_url AS poster                                -- poster
        FROM derived_video v
        JOIN derived_video_director vd ON vd.content_id = v.content_id
        JOIN derived_director d ON d.id = vd.director_id
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND d.name_romaji = ? OR d.name_kana = ?
          AND v.dvd_id IS NOT NULL
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', [director, director]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Year
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByYear(String year) async {
    if (await _validation() == false) return 0;

    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v 
      WHERE 1=1
        AND v.release_date LIKE ?
        AND v.dvd_id IS NOT NULL
    ''', ['$year%']);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByYear(String year) async {
    if (await _validation() == false) return [];

    final maps = await _db.rawQuery('''
        SELECT
          v.content_id AS id,                                         -- id
          v.dvd_id AS video_code,                                     -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,     -- title
          v.release_date AS release_date,                             -- release_date
          v.sample_url AS trailer,                                    -- trailer
          v.jacket_full_url AS fan_art,                               -- fan_art
          v.jacket_thumb_url AS poster                                -- poster
        FROM derived_video v
        LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
        WHERE 1=1
          AND v.release_date LIKE ?
          AND v.dvd_id IS NOT NULL
        ORDER BY
          v.release_date DESC
        LIMIT 10000
      ''', ['$year%']);
    return maps;
  }
}
