import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import '../../core/app_setting.dart';
import '_init_db.dart';

mixin DBR18 {
  static final _db = Get.find<DBService>().dbR18;

  static const _blacklistedPrefixes = [
    'TK', '7', '9', 'K9', 'FTKT', 'GOOE', 'JTKT', 'GTKT', 'DDMP', 'DMPXA', 'USTD', 'VWBS', 
    'HPXR', 'VWAS','TCBD', 'DAXA', 'TWUSS', 'PJXF', 'KKC', 'GNXF', 'JAXA', 
    'UHB', 'BPUH', 'GNXT', 'ZTKT', 'PB', 'D1', 'D2', 'D3', 'DK', 'BCQA', 'ANRS', 'SPUF', 'ANRM',
  ];

  static const _blacklistedSuffixes = [
    'BOD', 'DOD', 'Ta', 'Tb', 'Tc', 'Td', 'Te', 'TK',
    'TK1', 'TK2', 'TK3', 'EC', '4D', '5D', 'DL',
  ];

  static Map<String, dynamic> _buildFilterClause({ String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, }) {
    final clauses = <String>[];
    final args = <Object?>[];

    if (videoCode != null && videoCode.isNotEmpty) {
      clauses.add('v.dvd_id LIKE ?');
      args.add('%$videoCode%');
    }

    if (actressName != null && actressName.isNotEmpty) {
      clauses.add('EXISTS ('
          'SELECT 1 FROM derived_video_actress dva2 '
          'JOIN derived_actress da2 ON da2.id = dva2.actress_id '
          'WHERE dva2.content_id = v.content_id AND da2.name_romaji LIKE ?'
          ')');
      args.add('%$actressName%');
    }

    if (categories != null && categories.isNotEmpty) {
      final placeholders = List.filled(categories.length, '?').join(', ');
      clauses.add('v.content_id IN ('
          'SELECT vc2.content_id FROM derived_video_category vc2 '
          'JOIN derived_category dc2 ON dc2.id = vc2.category_id '
          'WHERE dc2.name_en IN ($placeholders) '
          'GROUP BY vc2.content_id '
          'HAVING COUNT(DISTINCT dc2.name_en) = ?'
          ')');
      args.addAll(categories);
      args.add(categories.length);
    }

    if (yearStart != null && yearEnd != null) {
      clauses.add('CAST(substr(v.release_date, 1, 4) AS INTEGER) BETWEEN ? AND ?');
      args.add(yearStart);
      args.add(yearEnd);
    }

    return {
      'sql': clauses.isEmpty ? '' : ' AND ${clauses.join(' AND ')}',
      'args': args,
    };
  }

  static Map<String, dynamic> _buildBlacklistClause({String column = 'v.dvd_id'}) {
    final clauses = <String>[];
    final args = <Object?>[];

    for (final prefix in _blacklistedPrefixes) {
      clauses.add('$column NOT LIKE ?');
      args.add('$prefix%');
    }

    for (final suffix in _blacklistedSuffixes) {
      clauses.add('$column NOT LIKE ?');
      args.add('%$suffix');
    }

    return {
      'sql': clauses.isEmpty ? '' : ' AND ${clauses.join(' AND ')}',
      'args': args,
    };
  }

  static Future<bool> _validation() async {
    var files = Glob('r18*.db').listSync(root: Get.find<AppSettingService>().appPath);
    files.sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) return false;

    if (await files[0].exists()) return true;
    return false;
  }

  static Future<int> getCountAllVideos() async {
    if (await _validation() == false) return 0;

    final blacklist = _buildBlacklistClause();
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
      SELECT count(*) as total FROM derived_video v
      WHERE v.dvd_id IS NOT NULL
      ${blacklist['sql']}
    ''', [...blacklist['args']]);
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

  static Future<List<Map<String, dynamic>>> search( String query, { int? page = 1, int? perPage = 100, String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, }) async {
    if (await _validation() == false) return [];

    final searchString = '%$query%';
    final limit = perPage ?? 100;
    final offset = ((page ?? 1) - 1) * limit;

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

    final filter = _buildFilterClause(videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd);
    final blacklist = _buildBlacklistClause();

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
      ${filter['sql']}
      ${blacklist['sql']}
    GROUP BY v.dvd_id
    ORDER BY v.release_date DESC
    LIMIT ? OFFSET ?
  ''', [searchString, searchString, searchString, ...filter['args'], ...blacklist['args'], limit, offset]);

    return maps;
  }

  static Future<int> getSearchCount( String query, { String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, }) async {
    if (await _validation() == false) return 0;

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

    final filter = _buildFilterClause(videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd);
    final blacklist = _buildBlacklistClause();

    final maps = await _db.rawQuery('''
    SELECT
      COUNT(DISTINCT v.dvd_id) AS total
    FROM derived_video v
    WHERE
      v.dvd_id IS NOT NULL AND v.dvd_id IN $subQuery
      AND v.release_date IS NOT NULL
      ${filter['sql']}
      ${blacklist['sql']}
  ''', [searchString, searchString, searchString, ...filter['args'], ...blacklist['args']]);

    return maps[0]['total'] as int;
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
    var whereClause = '';
    var whereArgs = [];

    if (q != null) {
      whereClause += ' AND s.name_en LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _db.rawQuery('''
      SELECT s.*, mv.max_release_date
      FROM derived_series s
      JOIN (
        SELECT series_id, MAX(release_date) AS max_release_date
        FROM derived_video
        GROUP BY series_id
      ) mv ON mv.series_id = s.id
      WHERE 1=1
        $whereClause
        AND s.name_en IS NOT NULL
      ORDER BY mv.max_release_date DESC
    ''', whereArgs);

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

    final blacklist = _buildBlacklistClause();
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
        ${blacklist['sql']}
        AND EXISTS (
          SELECT 1 FROM derived_video_actress dva2
          WHERE dva2.content_id = v.content_id
          GROUP BY dva2.content_id
          HAVING COUNT(dva2.actress_id) = 1
        );
    ''', [actressId, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByActress(
    int actressId, {
    bool singleActressMode = true,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
        ${blacklist['sql']}
        ${singleActressMode ? 'AND EXISTS (SELECT 1 FROM derived_video_actress dva2 WHERE dva2.content_id = v.content_id GROUP BY dva2.content_id HAVING COUNT(dva2.actress_id) = 1)' : ''}
        
      ORDER BY
        v.release_date DESC
      LIMIT ? OFFSET ?;
    ''', [actressId, ...blacklist['args'], limit, offset]);
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

  static Future<List<Map<String, dynamic>>> getAllVideosByCategory(
    String categoryName, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', [categoryName, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Label
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByLabel(String labelName) async {
    if (await _validation() == false) return 0;

    final blacklist = _buildBlacklistClause();
    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_label l ON l.id = v.label_id
      WHERE 1=1
        AND l.name_en = ?
        AND v.dvd_id IS NOT NULL
        ${blacklist['sql']}
    ''', [labelName, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByLabel(
    String labelName, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', [labelName, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Series
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosBySeries(String series) async {
    if (await _validation() == false) return 0;

    final blacklist = _buildBlacklistClause();
    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_series s ON s.id = v.series_id
      WHERE 1=1
        AND s.name_en LIKE ?
        AND v.dvd_id IS NOT NULL
        ${blacklist['sql']}
    ''', [series, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosBySeries(
    String series, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        GROUP BY
          v.dvd_id
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', [series, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Maker / Studio
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByStudio(String studio) async {
    if (await _validation() == false) return 0;

    final blacklist = _buildBlacklistClause();
    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v
      JOIN derived_maker m ON m.id = v.maker_id
      WHERE 1=1
        AND m.name_en = ? OR m.name_ja = ?
        AND v.dvd_id IS NOT NULL
        ${blacklist['sql']}
    ''', [studio, studio, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByStudio(
    String studio, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', [studio, studio, ...blacklist['args'], limit, offset]);
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

  static Future<List<Map<String, dynamic>>> getAllVideosByDirector(
    String director, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', [director, director, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Year
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByYear(String year) async {
    if (await _validation() == false) return 0;

    final blacklist = _buildBlacklistClause();
    final maps = await _db.rawQuery('''
      SELECT 
        COUNT(*) AS total
      FROM derived_video v 
      WHERE 1=1
        AND v.release_date LIKE ?
        AND v.dvd_id IS NOT NULL
        ${blacklist['sql']}
    ''', ['$year%', ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByYear(
    String year, {
    int page = 1,
    int perPage = 10000,
  }) async {
    if (await _validation() == false) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
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
          ${blacklist['sql']}
        ORDER BY
          v.release_date DESC
        LIMIT ? OFFSET ?
      ''', ['$year%', ...blacklist['args'], limit, offset]);
    return maps;
  }

  // new: get new release
  static Future<List<Map<String, dynamic>>> getNewRelease({
    int? page = 1,
    int? perPage = 100,
    String? videoCode,
    String? actressName,
    List<String>? categories,
    int? yearStart,
    int? yearEnd,
  }) async {
    if (await _validation() == false) return [];

    final yM = DateTime.now().toStringEx(format: 'yyyy-MM');
    final dd = DateTime.now().toStringEx(format: 'dd');
    final limit = perPage ?? 100;
    final offset = ((page ?? 1) - 1) * limit;

    final filter = _buildFilterClause(
      videoCode: videoCode,
      actressName: actressName,
      categories: categories,
      yearStart: yearStart,
      yearEnd: yearEnd,
    );
    final blacklist = _buildBlacklistClause();

    final maps = await _db.rawQuery('''
    SELECT
      v.content_id AS id,
      v.dvd_id AS video_code,
      COALESCE(t.target_en, v.title_en, v.title_ja) AS title,
      v.runtime_mins AS duration,
      v.release_date AS release_date,
      v.sample_url AS trailer,
      v.jacket_full_url AS fan_art,
      v.jacket_thumb_url AS poster,
      v.gallery_full_first AS ssfirst,
      v.gallery_full_last AS sslast,
      GROUP_CONCAT(dc.name_en, ', ') AS categories,
      GROUP_CONCAT(da.name_romaji, ', ') AS actresses
    FROM derived_video v
    LEFT JOIN machine_translation t ON t.source_ja = v.title_ja
    LEFT JOIN derived_video_category dvc ON dvc.content_id = v.content_id
    LEFT JOIN derived_category dc ON dc.id = dvc.category_id
    LEFT JOIN derived_video_actress dva ON dva.content_id = v.content_id
    LEFT JOIN derived_actress da ON da.id = dva.actress_id
    WHERE
      v.dvd_id IS NOT NULL 
      AND v.release_date IS NOT NULL
      AND v.runtime_mins IS NOT NULL
      AND v.label_id IS NOT NULL
      AND v.dvd_id IN (
        SELECT v2.dvd_id FROM derived_video v2 
        WHERE 1=1
          AND dvd_id IS NOT NULL
          AND release_date >= ? AND release_date <= ?
      )
      ${filter['sql']}
      ${blacklist['sql']}
    GROUP BY v.dvd_id
    ORDER BY v.release_date DESC
    LIMIT ? OFFSET ?
  ''', ['$yM-01', '$yM-$dd', ...filter['args'], ...blacklist['args'], limit, offset]);

    return maps;
  }

  static Future<int> getNewReleaseCount({
    String? videoCode,
    String? actressName,
    List<String>? categories,
    int? yearStart,
    int? yearEnd,
  }) async {
    if (await _validation() == false) return 0;

    final yM = DateTime.now().toStringEx(format: 'yyyy-MM');
    final dd = DateTime.now().toStringEx(format: 'dd');

    final filter = _buildFilterClause(
      videoCode: videoCode,
      actressName: actressName,
      categories: categories,
      yearStart: yearStart,
      yearEnd: yearEnd,
    );
    final blacklist = _buildBlacklistClause();

    final maps = await _db.rawQuery('''
    SELECT
      COUNT(DISTINCT v.dvd_id) AS total
    FROM derived_video v
    WHERE
      v.dvd_id IS NOT NULL 
      AND v.release_date IS NOT NULL
      AND v.runtime_mins IS NOT NULL
      AND v.label_id IS NOT NULL
      AND v.dvd_id IN (
        SELECT v2.dvd_id FROM derived_video v2 
        WHERE 1=1
          AND dvd_id IS NOT NULL
          AND release_date >= ? AND release_date <= ?
      )
      ${filter['sql']}
      ${blacklist['sql']}
  ''', ['$yM-01', '$yM-$dd', ...filter['args'], ...blacklist['args']]);

    return maps[0]['total'] as int;
  }
}
