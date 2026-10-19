import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';
import '_init_db.dart';

enum ActressMode { all, single, multi }

mixin DBR18 {
  static Database? get _db => Get.find<DBService>().dbR18;

  static Future<T> _logQueryTime<T>(Future<T> Function() run) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await run();
    } finally {
      stopwatch.stop();
      final funcName = _resolveCaller();
      AppLog.logD('EXEC: $funcName | ${stopwatch.elapsedMilliseconds} ms');
    }
  }

  static String _resolveCaller() {
    final trace = StackTrace.current.toString().split('\n');
    for (final frame in trace) {
      final match = RegExp(r'#\d+\s+([^\s(]+)').firstMatch(frame);
      if (match == null) continue;

      final fn = match.group(1)!;
      // Skip internal helpers
      if (fn.startsWith('DBR18._')) continue;
      if (fn.contains('_logQueryTime') || fn.contains('_rawQuery') || fn.contains('_query')) continue;

      // Prefer DBR18 public methods; otherwise return first non-helper frame.
      if (fn.startsWith('DBR18.')) return fn;
      if (!fn.startsWith('_')) return fn;
    }
    return 'unknown';
  }

  static Future<List<Map<String, dynamic>>> _rawQuery(
    String sql, [
    List<Object?>? args,
  ]) async {
    final db = _db;
    if (db == null) return [];
    final boundArgs = args ?? const [];
    return _logQueryTime<List<Map<String, dynamic>>>(
      () => db.rawQuery(sql, boundArgs),
    );
  }

  static Future<List<Map<String, dynamic>>> _query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = _db;
    if (db == null) return [];
    final boundArgs = whereArgs ?? const [];
    return _logQueryTime<List<Map<String, dynamic>>>(
      () => db.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: boundArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      ),
    );
  }

  static const _blacklistedPrefixes = [
    'TK', '7', '9', 'K9', 'FTKT', 'GOOE', 'JTKT', 'GTKT', 'DDMP', 'DMPXA', 'USTD', 'VWBS', 
    'HPXR', 'VWAS','TCBD', 'DAXA', 'TWUSS', 'PJXF', 'KKC', 'GNXF', 'JAXA', 
    'UHB', 'BPUH', 'GNXT', 'ZTKT', 'PB', 'D1', 'D2', 'D3', 'DK', 'BCQA', 'ANRS', 'SPUF', 'ANRM',
  ];

  static const _blacklistedSuffixes = [
    'BOD', 'DOD', 'Ta', 'Tb', 'Tc', 'Td', 'Te', 'TK',
    'TK1', 'TK2', 'TK3', 'EC', '4D', '5D', 'DL',
  ];

  static Map<String, dynamic> _buildFilterClause({ bool correlatedRelations = false, bool matchAllCategories = false, String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, int? durationMin, int? durationMax, ActressMode actressMode = ActressMode.all, bool onlySeries = false, }) {
    final clauses = <String>[];
    final args = <Object?>[];

    if (videoCode != null && videoCode.isNotEmpty) {
      clauses.add("(v.video_code LIKE ? OR REPLACE(v.video_code, '-', '') LIKE ? OR v.content_id LIKE ?)");
      args.add('%${videoCode.trim()}%');
      args.add('%${videoCode.trim().replaceAll('-', '')}%');
      args.add('%${videoCode.trim().replaceAll('-', '')}%');
    }

    if (actressName != null && actressName.isNotEmpty) {
      clauses.add('${correlatedRelations ? 'EXISTS (' : 'v.content_id IN ('}'
          'SELECT dva2.content_id FROM '
          '${correlatedRelations ? 'derived_video_actress dva2 JOIN derived_actress da2' : 'derived_actress da2 CROSS JOIN derived_video_actress dva2'} '
          'ON da2.id = dva2.actress_id '
          'WHERE ${correlatedRelations ? 'dva2.content_id = v.content_id AND ' : ''}'
          '(da2.name_romaji LIKE ? OR da2.name_kana LIKE ? OR da2.name_kanji LIKE ?)'
          ')');
      args.add('%$actressName%');
      args.add('%$actressName%');
      args.add('%$actressName%');
    }

    if (categories != null && categories.isNotEmpty) {
      final placeholders = List.filled(categories.length, '?').join(', ');
      clauses.add('${correlatedRelations ? 'EXISTS (' : 'v.content_id IN ('}'
          'SELECT vc2.content_id FROM derived_video_category vc2 '
          'JOIN derived_category dc2 ON dc2.id = vc2.category_id '
          'WHERE ${correlatedRelations ? 'vc2.content_id = v.content_id AND ' : ''}dc2.name_en IN ($placeholders)'
          '${matchAllCategories ? ' GROUP BY vc2.content_id HAVING COUNT(DISTINCT dc2.name_en) = ?' : ''}'
          ')');
      args.addAll(categories);
      if (matchAllCategories) args.add(categories.toSet().length);
    }

    if (yearStart != null && yearEnd != null) {
      clauses.add('CAST(substr(v.release_date, 1, 4) AS INTEGER) BETWEEN ? AND ?');
      args.add(yearStart);
      args.add(yearEnd);
    }

    if (durationMin != null || durationMax != null) clauses.add('v.runtime_mins > 0');
    if (durationMin != null) {
      clauses.add('v.runtime_mins >= ?');
      args.add(durationMin);
    }
    if (durationMax != null) {
      clauses.add('v.runtime_mins <= ?');
      args.add(durationMax);
    }

    if (onlySeries) clauses.add("EXISTS (SELECT 1 FROM derived_series s WHERE s.id = v.series_id AND COALESCE(NULLIF(TRIM(s.name_en), ''), NULLIF(TRIM(s.name_ja), '')) IS NOT NULL)");
    final sql = clauses.isEmpty ? '' : ' AND ${clauses.join(' AND ')}';
    return {
      'sql': '$sql${actressMode == ActressMode.all ? '' : ' ${_actressModeClause(actressMode)}'}',
      'args': args,
    };
  }

  static Map<String, dynamic> _buildBlacklistClause({String column = 'v.video_code'}) => {
    'sql': ' AND (${_advancedVideos.replaceAll('video_code', column)})',
    'args': <Object?>[],
  };

  static String _normalizeCode(String code) {
    final value = code.trim().toUpperCase();
    final match = RegExp(r'^([A-Z]{2,})([0-9]{2,5})$').firstMatch(value);
    return match == null ? value : '${match[1]}-${match[2]}';
  }

  static const _preferredVideo = "CASE WHEN NULLIF(TRIM(v.dvd_id), '') IS NULL THEN 1 ELSE 0 END, v.release_date DESC, v.content_id, v.rowid";

  static bool _isReady() => _db != null;

  static Future<int> getCountAllVideos() async {
    if (!_isReady()) return 0;
    final List<Map<String, dynamic>> maps = await _rawQuery('''
      SELECT count(*) as total FROM derived_video v
    ''', []);
    return maps[0]['total'] as int;
  }

  static Future<Map<String, dynamic>?> getVideo(String code) async {
    if (!_isReady()) return null;

    final maps = await _rawQuery('''
        SELECT
          v.content_id as id,                                         -- id
          v.video_code as video_code,                                     -- video_code
          COALESCE(t.target_en, v.title_en, v.title_ja) AS title,     -- title
          v.title_ja,                                                 -- title_ja
          COALESCE(NULLIF(TRIM(s.name_en), ''), NULLIF(TRIM(s.name_ja), '')) AS series, -- series
          COALESCE(NULLIF(TRIM(m.name_en), ''), NULLIF(TRIM(m.name_ja), '')) AS studio,                   -- studio/maker
          COALESCE(NULLIF(TRIM(l.name_en), ''), NULLIF(TRIM(l.name_ja), '')) AS label,                                         -- label
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
          AND v.video_code = ?
        ORDER BY $_preferredVideo
        LIMIT 1
      ''', [_normalizeCode(code)]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  static Future<Map<String, String>> getPosterByCodes(List<String> codes) async {
    if (!_isReady()) return {};
    final uniqueCodes = codes.where((e) => e.trim().isNotEmpty).map(_normalizeCode).toSet().toList();
    if (uniqueCodes.isEmpty) return {};

    final result = <String, String>{};
    for (var offset = 0; offset < uniqueCodes.length; offset += 900) {
      final batch = uniqueCodes.skip(offset).take(900).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      final maps = await _rawQuery('''
        SELECT
          v.video_code AS video_code,
          v.jacket_thumb_url AS poster
        FROM derived_video v
        WHERE v.video_code IN ($placeholders)
        ORDER BY $_preferredVideo
      ''', batch);

      for (final row in maps) {
        final code = (row['video_code'] ?? '').toString();
        final poster = (row['poster'] ?? '').toString();
        if (code.isEmpty || poster.isEmpty) continue;
        result.putIfAbsent(code, () => poster);
      }
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> _catalogQuery(String where, List<Object?> args, {String search = '', List<Object?> searchArgs = const []}) => _rawQuery('''
    WITH matched AS MATERIALIZED (
      SELECT v.content_id, v.video_code
      FROM page CROSS JOIN derived_video v ON v.video_code = page.video_code WHERE $where
    ), page AS (
      SELECT v.rowid AS video_rowid, v.video_code, v.release_date
      FROM derived_video v INDEXED BY idx_dv_catalog_date
      WHERE ${search.isEmpty ? '' : '$search AND '}$where
        AND NOT EXISTS (
          SELECT 1 FROM derived_video newer WHERE newer.video_code = v.video_code
            AND ${where.replaceAll('v.', 'newer.')}
            AND (newer.release_date > v.release_date OR (newer.release_date = v.release_date AND newer.rowid < v.rowid))
        )
      ORDER BY v.release_date DESC, v.video_code LIMIT ? OFFSET ?
    ), categories AS (
      SELECT m.video_code, GROUP_CONCAT(DISTINCT dc.name_en) AS categories
      FROM matched m
      JOIN derived_video_category dvc ON dvc.content_id = m.content_id
      JOIN derived_category dc ON dc.id = dvc.category_id GROUP BY m.video_code
    ), actresses AS (
      SELECT m.video_code, GROUP_CONCAT(DISTINCT da.name_romaji) AS actresses
      FROM matched m
      JOIN derived_video_actress dva ON dva.content_id = m.content_id
      JOIN derived_actress da ON da.id = dva.actress_id GROUP BY m.video_code
    )
    SELECT v.content_id AS id, v.video_code, v.runtime_mins AS duration,
      COALESCE((SELECT t.target_en FROM machine_translation t WHERE t.source_ja = v.title_ja LIMIT 1), v.title_en, v.title_ja) AS title,
      page.release_date, v.sample_url AS trailer, v.jacket_full_url AS fan_art, v.jacket_thumb_url AS poster,
      v.gallery_full_first AS ssfirst, v.gallery_full_last AS sslast, categories.categories, actresses.actresses,
      (SELECT COUNT(DISTINCT dva.actress_id) FROM derived_video_actress dva WHERE dva.content_id = v.content_id) AS actress_count,
      (SELECT COALESCE(NULLIF(TRIM(s.name_en), ''), NULLIF(TRIM(s.name_ja), '')) FROM derived_series s WHERE s.id = v.series_id LIMIT 1) AS series
    FROM page JOIN derived_video v ON v.rowid = page.video_rowid
    LEFT JOIN categories ON categories.video_code = page.video_code
    LEFT JOIN actresses ON actresses.video_code = page.video_code
    ORDER BY page.release_date DESC, v.video_code
  ''', [...args.take(args.length - 2), ...searchArgs, ...args.take(args.length - 2), ...args]);

  static Future<List<Map<String, dynamic>>> search(String query, { bool matchAllCategories = false, int? page = 1, int? perPage = 100, String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, int? durationMin, int? durationMax, ActressMode actressMode = ActressMode.all, bool onlySeries = false}) async {
    if (!_isReady()) return [];
    if (query.trim().isEmpty) return getByFilter(matchAllCategories: matchAllCategories, page: page, perPage: perPage, videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries);

    final searchString = '%${query.trim()}%';
    final contentSearch = '%${query.trim().replaceAll('-', '')}%';
    final limit = perPage ?? 100;
    final offset = ((page ?? 1) - 1) * limit;

    final subQuery = '''
    (
      SELECT v2.video_code FROM derived_video v2
      WHERE 
        v2.video_code LIKE ? OR REPLACE(v2.video_code, '-', '') LIKE ? OR v2.content_id LIKE ? OR v2.title_en LIKE ?
      UNION
      SELECT v3.video_code FROM machine_translation t2
      CROSS JOIN derived_video v3 ON v3.title_ja = t2.source_ja WHERE t2.target_en LIKE ?
    )
  ''';

    final filter = _buildFilterClause(correlatedRelations: true, matchAllCategories: matchAllCategories,videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries);
    final blacklist = _buildBlacklistClause();

    final maps = await _catalogQuery('''
      v.video_code IS NOT NULL
      AND v.release_date IS NOT NULL
      ${filter['sql']}
      ${blacklist['sql']}
  ''', [...filter['args'], ...blacklist['args'], limit, offset], search: 'v.video_code IN $subQuery', searchArgs: [searchString, contentSearch, contentSearch, searchString, searchString]);

    return maps;
  }

  static Future<int> getSearchCount(String query, {bool matchAllCategories = false,String? videoCode, String? actressName, List<String>? categories, int? yearStart, int? yearEnd, int? durationMin, int? durationMax, ActressMode actressMode = ActressMode.all, bool onlySeries = false}) async {
    if (!_isReady()) return 0;
    if (query.trim().isEmpty) return getByFilterCount(matchAllCategories: matchAllCategories, videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries);

    final searchString = '%${query.trim()}%';
    final contentSearch = '%${query.trim().replaceAll('-', '')}%';
    final subQuery = '''
    (
      SELECT v2.video_code FROM derived_video v2
      WHERE 
        v2.video_code LIKE ? OR REPLACE(v2.video_code, '-', '') LIKE ? OR v2.content_id LIKE ? OR v2.title_en LIKE ?
      UNION
      SELECT v3.video_code FROM machine_translation t2
      CROSS JOIN derived_video v3 ON v3.title_ja = t2.source_ja WHERE t2.target_en LIKE ?
    )
  ''';

    final filter = _buildFilterClause(matchAllCategories: matchAllCategories,videoCode: videoCode, actressName: actressName, categories: categories, yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries);
    final blacklist = _buildBlacklistClause();

    final maps = await _rawQuery('''
    SELECT
      COUNT(DISTINCT v.video_code) AS total
    FROM derived_video v
    WHERE
      v.video_code IS NOT NULL AND v.video_code IN $subQuery
      AND v.release_date IS NOT NULL
      ${filter['sql']}
      ${blacklist['sql']}
  ''', [searchString, contentSearch, contentSearch, searchString, searchString, ...filter['args'], ...blacklist['args']]);

    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getByFilter({
    bool matchAllCategories = false,
    int? page = 1,
    int? perPage = 100,
    String? videoCode,
    String? actressName,
    List<String>? categories,
    int? yearStart,
    int? yearEnd, int? durationMin, int? durationMax,
    ActressMode actressMode = ActressMode.all, bool onlySeries = false,
  }) async {
    if (!_isReady()) return [];

    final limit = perPage ?? 100;
    final offset = ((page ?? 1) - 1) * limit;
    final filter = _buildFilterClause(
      correlatedRelations: true,
      matchAllCategories: matchAllCategories,
      videoCode: videoCode,
      actressName: actressName,
      categories: categories,
      yearStart: yearStart,
      yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
    );
    final blacklist = _buildBlacklistClause();

    final maps = await _catalogQuery('''
      v.video_code IS NOT NULL
      AND v.release_date IS NOT NULL
      ${filter['sql']}
      ${blacklist['sql']}
  ''', [...filter['args'], ...blacklist['args'], limit, offset]);

    return maps;
  }

  static Future<int> getByFilterCount({
    bool matchAllCategories = false,
    String? videoCode,
    String? actressName,
    List<String>? categories,
    int? yearStart,
    int? yearEnd, int? durationMin, int? durationMax,
    ActressMode actressMode = ActressMode.all, bool onlySeries = false,
  }) async {
    if (!_isReady()) return 0;

    final filter = _buildFilterClause(
      correlatedRelations: videoCode != null && videoCode.trim().isNotEmpty,
      matchAllCategories: matchAllCategories,
      videoCode: videoCode,
      actressName: actressName,
      categories: categories,
      yearStart: yearStart,
      yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
    );
    final blacklist = _buildBlacklistClause();

    final maps = await _rawQuery('''
    SELECT
      COUNT(DISTINCT v.video_code) AS total
    FROM derived_video v
    WHERE
      v.video_code IS NOT NULL
      AND v.release_date IS NOT NULL
      ${filter['sql']}
      ${blacklist['sql']}
  ''', [...filter['args'], ...blacklist['args']]);

    return maps[0]['total'] as int;
  }

  static ({String join, String id, String name, String jp, String search}) _advancedGroup(String kind) {
    switch (kind) {
      case 'Actress': return (
        join: 'JOIN derived_video_actress link ON link.content_id = v.content_id JOIN derived_actress g ON g.id = link.actress_id',
        id: 'g.id', name: "COALESCE(NULLIF(TRIM(g.name_romaji), ''), NULLIF(TRIM(g.name_kanji), ''), NULLIF(TRIM(g.name_kana), ''))",
        jp: "COALESCE(NULLIF(TRIM(g.name_kanji), ''), g.name_kana)",
        search: "COALESCE(g.name_romaji, '') || ' ' || COALESCE(g.name_kanji, '') || ' ' || COALESCE(g.name_kana, '')",
      );
      case 'Category':
      case 'Series': return (
        join: kind == 'Category'
            ? 'JOIN derived_video_category link ON link.content_id = v.content_id JOIN derived_category g ON g.id = link.category_id'
            : 'JOIN derived_series g ON g.id = v.series_id',
        id: 'g.id', name: "COALESCE(NULLIF(TRIM(g.name_en), ''), NULLIF(TRIM(g.name_ja), ''))",
        jp: 'g.name_ja', search: "COALESCE(g.name_en, '') || ' ' || COALESCE(g.name_ja, '')",
      );
      case 'Year': return (
        join: '', id: "strftime('%Y', v.release_date)", name: "strftime('%Y', v.release_date)",
        jp: "''", search: "strftime('%Y', v.release_date)",
      );
      default: throw ArgumentError('Unknown R18 group: $kind');
    }
  }

  // Match the local video-code validator before counting or selecting catalog results.
  static String get _advancedVideos {
    const prefix = "substr(video_code, 1, instr(video_code, '-') - 1)";
    const tail = "substr(video_code, instr(video_code, '-') + 1)";
    const serial = "CASE WHEN instr($tail, '-') = 0 THEN $tail ELSE substr($tail, 1, instr($tail, '-') - 1) END";
    const suffix = "CASE WHEN instr($tail, '-') = 0 THEN 'x' ELSE substr($tail, instr($tail, '-') + 1) END";
    final blacklist = [
      for (final prefix in _blacklistedPrefixes) "video_code NOT LIKE '$prefix%'",
      for (final suffix in _blacklistedSuffixes) "video_code NOT LIKE '%$suffix'",
    ].join(' AND ');
    // Literal predicates let SQLite use the converter's matching partial index.
    return '''
      length($prefix) >= 2 AND $prefix NOT GLOB '*[^A-Za-z]*'
          AND length(ltrim(($serial), 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')) BETWEEN 2 AND 5
          AND ltrim(($serial), 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz') NOT GLOB '*[^0-9]*'
          AND ($suffix) != '' AND ($suffix) NOT GLOB '*[^A-Za-z0-9]*'
          AND $blacklist
    ''';
  }

  static Database? _advancedCacheDatabase;
  // ponytail: cache four catalog lists per connection; invalidate when the R18 snapshot changes.
  static final _advancedGroups = <String, Future<List<Map<String, dynamic>>>>{};

  static Future<List<Map<String, dynamic>>> getAdvancedSearchGroups(String kind, {String? q}) async {
    if (!_isReady()) return [];
    if (!identical(_advancedCacheDatabase, _db)) {
      _advancedCacheDatabase = _db;
      _advancedGroups.clear();
    }
    final task = _advancedGroups.putIfAbsent(kind, () => _loadAdvancedSearchGroups(kind));
    final List<Map<String, dynamic>> rows;
    try {
      rows = await task;
    } catch (_) {
      _advancedGroups.removeWhere((key, value) => key == kind && identical(value, task));
      rethrow;
    }
    final search = (q ?? '').trim().toLowerCase();
    return rows.where((row) => search.isEmpty || '${row['search_text']}'.toLowerCase().contains(search)).toList();
  }

  static Future<List<Map<String, dynamic>>> _loadAdvancedSearchGroups(String kind) async {
    final group = _advancedGroup(kind);
    final isYear = kind == 'Year';
    final table = switch (kind) {
      'Series' => 'derived_series', 'Category' => 'derived_category', _ => 'derived_actress',
    };
    final name = isYear ? 'summary.id' : group.name;
    return _rawQuery('''
      SELECT summary.id, $name AS name_en, ${isYear ? "''" : group.jp} AS name_ja,
        ${isYear ? 'summary.id' : group.search} AS search_text, summary.video_count, summary.max_release_date
      FROM kuraku_catalog_groups_v2 summary ${isYear ? '' : 'JOIN $table g ON g.id = summary.id'}
      WHERE summary.kind = ? AND $name IS NOT NULL
      ORDER BY max_release_date DESC, name_en COLLATE NOCASE, summary.id
    ''', [kind]);
  }

  static Future<List<Map<String, dynamic>>> getAdvancedSearchVideos(String kind, Object id) async {
    if (!_isReady()) return [];
    final group = _advancedGroup(kind);
    final index = switch (kind) {
      'Series' => 'idx_dv_advanced_codes', 'Year' => 'idx_dv_advanced_year', _ => 'idx_dv_advanced_content',
    };
    final videos = await _browseQuery('''
      SELECT v.rowid AS video_rowid, MAX(date(v.release_date)) AS release_date
      FROM derived_video v INDEXED BY $index ${group.join}
      WHERE $_advancedVideos AND ${group.id} = ?
      GROUP BY v.video_code ORDER BY date(v.release_date) DESC, v.video_code
    ''', [id], ignoreEmptyTitle: true);
    final categories = await getCategoriesByVideoCodes(videos.map((video) => '${video['video_code']}').toList());
    return [for (final video in videos) {
      ...video,
      'categories': categories[video['video_code']] ?? <String>[],
    }];
  }

  static Future<List<Map<String, dynamic>>> getAllActress({String? q}) async {
    if (!_isReady()) return [];

    var whereClause = '''
    (
      (
        name_romaji IS NOT NULL
        AND TRIM(name_romaji) != ''
        AND name_romaji GLOB '[a-zA-Z]*'
        AND name_romaji NOT GLOB '*[0-9]*'
        AND name_romaji NOT GLOB '*[(-)]*'
        AND name_romaji NOT GLOB '*[!@#\$%%^&*()_-+=~`{}|:;"<>?,./]*'
        AND LENGTH(name_romaji) >= 3
      )
      OR (
        name_kana IS NOT NULL
        AND TRIM(name_kana) != ''
      )
      OR (
        name_kanji IS NOT NULL
        AND TRIM(name_kanji) != ''
      )
    )
  ''';
    final whereArgs = <Object?>[];

    if (q != null && q.trim().isNotEmpty) {
      whereClause += ' AND (name_romaji LIKE ? OR name_kana LIKE ? OR name_kanji LIKE ?)';
      whereArgs.add('%$q%');
      whereArgs.add('%$q%');
      whereArgs.add('%$q%');
    }

    final maps = await _query(
      'derived_actress',
      columns: ['*', "COALESCE(NULLIF(name_romaji, ''), NULLIF(name_kana, ''), name_kanji) AS name_en"],
      where: whereClause,
      whereArgs: whereArgs,
      groupBy: "COALESCE(NULLIF(name_romaji, ''), NULLIF(name_kana, ''), name_kanji)",
      orderBy: 'name_en COLLATE NOCASE',
    );

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getActress(String code) async {
    if (!_isReady()) return [];

    final maps = await _rawQuery('''
        SELECT DISTINCT 
          a.*
        FROM derived_video_actress va
        JOIN derived_video v ON v.content_id = va.content_id
        JOIN derived_actress a ON a.id = va.actress_id
        WHERE 1=1
          AND v.video_code = ?
      ''', [_normalizeCode(code)]);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getAllSeries({String? q}) async {
    if (!_isReady()) return [];
    final whereArgs = <Object?>[];

    var filter = 'WHERE s.name_en IS NOT NULL';
    if (q != null) {
      filter += ' AND s.name_en LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _rawQuery('''
        SELECT * FROM (
          SELECT
            s.*,
            (SELECT MAX(release_date) FROM derived_video v WHERE v.series_id = s.id) AS max_release_date
          FROM derived_series s
          $filter
        ) x
        WHERE x.max_release_date IS NOT NULL
        ORDER BY x.max_release_date DESC
      ''', whereArgs);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getAllCategories({String? q}) async {
    if (!_isReady()) return [];

    var whereClause = 'name_en IS NOT NULL';
    final whereArgs = <Object?>[];

    if (q != null) {
      whereClause += ' AND name_en LIKE ?';
      whereArgs.add('%$q%');
    }

    final maps = await _query(
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
    if (!_isReady()) return [];

    final maps = await _rawQuery('''
        SELECT DISTINCT
          cat.id AS id, 
          cat.name_en AS category
        FROM derived_video_category c 
        JOIN derived_video v ON v.content_id = c.content_id
        JOIN derived_category cat ON cat.id = c.category_id
        WHERE 1=1
          AND v.video_code = ?
          AND cat.name_en IS NOT NULL
      ''', [_normalizeCode(code)]);

    return maps;
  }

  static Future<Map<String, List<String>>> getCategoriesByVideoCodes(List<String> videoCodes) async {
    if (!_isReady() || videoCodes.isEmpty) return {};

    final codes = videoCodes
        .map(_normalizeCode)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (codes.isEmpty) return {};

    final grouped = <String, Set<String>>{};
    for (var offset = 0; offset < codes.length; offset += 900) {
      final batch = codes.skip(offset).take(900).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      final rows = await _rawQuery('''
        SELECT
          v.video_code AS video_code,
          cat.name_en AS category
        FROM derived_video_category c
        JOIN derived_video v ON v.content_id = c.content_id
        JOIN derived_category cat ON cat.id = c.category_id
        WHERE v.video_code IN ($placeholders)
          AND cat.name_en IS NOT NULL
      ''', batch);

      for (final row in rows) {
        final code = '${row['video_code'] ?? ''}'.trim();
        final category = '${row['category'] ?? ''}'.trim();
        if (code.isEmpty || category.isEmpty) continue;

        grouped.putIfAbsent(code, () => <String>{}).add(category);
      }

    }

    final out = <String, List<String>>{};
    grouped.forEach((code, categories) {
      final sorted = categories.toList()..sort();
      out[code] = sorted;
    });

    return out;
  }

  static Future<Map<String, dynamic>?> getDirector(String code) async {
    if (!_isReady()) return null;

    final maps = await _rawQuery('''
        SELECT
          d.*,
          COALESCE(NULLIF(TRIM(d.name_romaji), ''), NULLIF(TRIM(d.name_kanji), ''), NULLIF(TRIM(d.name_kana), '')) AS director
        FROM derived_director d
        WHERE d.id IN (
          SELECT vd.director_id
          FROM derived_video_director vd
          WHERE vd.content_id = (
            SELECT v.content_id
            FROM derived_video v
            WHERE v.video_code = ?
              AND EXISTS (SELECT 1 FROM derived_video_director link WHERE link.content_id = v.content_id)
            ORDER BY $_preferredVideo
            LIMIT 1
          )
        )
        LIMIT 1
      ''', [_normalizeCode(code)]);

    return maps.isNotEmpty ? maps[0] : null;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Actress
  // ────────────────────────────────────────────────────────────────
  static String _actressModeClause(ActressMode mode) {
    if (mode == ActressMode.all) return '';
    return 'AND EXISTS (SELECT 1 FROM derived_video_actress dva2 WHERE dva2.content_id = v.content_id GROUP BY dva2.content_id HAVING COUNT(DISTINCT dva2.actress_id) ${mode == ActressMode.single ? '=' : '>'} 1)';
  }

  static Future<List<Map<String, dynamic>>> _browseQuery(String sql, List<Object?> args, {String extraColumns = '', bool ignoreEmptyTitle = false}) => _rawQuery('''
    WITH page AS ($sql)
    SELECT
      v.content_id AS id,
      v.video_code AS video_code,
      v.runtime_mins AS duration,
      COALESCE((SELECT ${ignoreEmptyTitle ? "NULLIF(t.target_en, '')" : 't.target_en'} FROM machine_translation t WHERE t.source_ja = v.title_ja LIMIT 1), ${ignoreEmptyTitle ? "NULLIF(v.title_en, '')" : 'v.title_en'}, v.title_ja) AS title,
      page.release_date AS release_date,
      v.sample_url AS trailer,
      v.jacket_full_url AS fan_art,
      v.jacket_thumb_url AS poster,
      (SELECT COUNT(DISTINCT dva.actress_id) FROM derived_video_actress dva WHERE dva.content_id = v.content_id) AS actress_count,
      (SELECT COALESCE(NULLIF(TRIM(s.name_en), ''), NULLIF(TRIM(s.name_ja), '')) FROM derived_series s WHERE s.id = v.series_id LIMIT 1) AS series
      $extraColumns
    FROM page
    JOIN derived_video v ON v.rowid = page.video_rowid
    ORDER BY page.release_date DESC, v.video_code
  ''', args);

  static ({String sql, List<Object?> args}) _catalogNameFilter(String name, List<String> columns, {bool like = false}) {
    final normalized = name.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r').replaceAll(r'\t', '\t').trim();
    if (normalized.isEmpty) return (sql: '0', args: []);
    // SQLite's default TRIM only removes ASCII spaces; match Dart's Unicode trim.
    const whitespace = 'CHAR(9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288, 65279)';
    final comparisons = columns.map((column) {
      final value = "TRIM(REPLACE(REPLACE(REPLACE($column, '\\n', CHAR(10)), '\\r', CHAR(13)), '\\t', CHAR(9)), $whitespace)";
      return '$value ${like ? 'LIKE' : '='} ?';
    });
    return (sql: '(${comparisons.join(' OR ')})', args: List<Object?>.filled(columns.length, normalized));
  }

  static Future<int> getCountAllVideosByActress(int actressId, {ActressMode actressMode = ActressMode.single}) async {
    if (!_isReady()) return 0;

    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT
        COUNT(DISTINCT v.video_code) AS total
      FROM
        derived_video v
        JOIN derived_video_actress dva ON dva.content_id = v.content_id
        JOIN derived_actress da ON da.id = dva.actress_id
      WHERE
        v.video_code IS NOT NULL
        AND da.id = ?
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)};
    ''', [actressId, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByActress(
    int actressId, {
    ActressMode actressMode = ActressMode.single,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
      SELECT
        da.id AS actress_id,
        v.rowid AS video_rowid,
        MAX(v.release_date) AS release_date
      FROM
        derived_video v
      JOIN derived_video_actress dva ON dva.content_id = v.content_id
      JOIN derived_actress da ON da.id = dva.actress_id
      WHERE 1=1
        AND v.video_code IS NOT NULL
        AND da.id = ?
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
        
      GROUP BY v.video_code
      ORDER BY
        v.release_date DESC, v.video_code
      LIMIT ? OFFSET ?
    ''', [actressId, ...blacklist['args'], limit, offset], extraColumns: ', page.actress_id');
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Category
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByCategory(String categoryName, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;

    final nameFilter = _catalogNameFilter(categoryName, ['c.name_en', 'c.name_ja']);
    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT 
        COUNT(DISTINCT v.video_code) AS total
      FROM derived_video v
      WHERE 1=1
        AND v.content_id IN (SELECT vc.content_id FROM derived_video_category vc WHERE vc.category_id IN (SELECT c.id FROM derived_category c WHERE ${nameFilter.sql}))
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...nameFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByCategory(
    String categoryName, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final nameFilter = _catalogNameFilter(categoryName, ['c.name_en', 'c.name_ja']);
    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v
        WHERE 1=1
          AND v.content_id IN (SELECT vc.content_id FROM derived_video_category vc WHERE vc.category_id IN (SELECT c.id FROM derived_category c WHERE ${nameFilter.sql}))
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...nameFilter.args, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Label
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByLabel(String labelName, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;

    final nameFilter = _catalogNameFilter(labelName, ['l.name_en', 'l.name_ja']);
    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT 
        COUNT(DISTINCT v.video_code) AS total
      FROM derived_video v
      WHERE 1=1
        AND v.label_id IN (SELECT l.id FROM derived_label l WHERE ${nameFilter.sql})
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...nameFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByLabel(
    String labelName, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final nameFilter = _catalogNameFilter(labelName, ['l.name_en', 'l.name_ja']);
    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v
        WHERE 1=1
          AND v.label_id IN (SELECT l.id FROM derived_label l WHERE ${nameFilter.sql})
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...nameFilter.args, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Series
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosBySeries(String series, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;
    final nameFilter = _catalogNameFilter(series, ['name_en', 'name_ja'], like: true);
    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT COUNT(DISTINCT v.video_code) AS total
      FROM derived_video v
      WHERE v.series_id IN (SELECT id FROM derived_series WHERE ${nameFilter.sql})
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...nameFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosBySeries(
    String series, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final nameFilter = _catalogNameFilter(series, ['name_en', 'name_ja'], like: true);
    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v INDEXED BY idx_dv_catalog_series
        WHERE 1=1
          AND v.series_id IN (SELECT id FROM derived_series WHERE ${nameFilter.sql})
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...nameFilter.args, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Maker / Studio
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByStudio(String studio, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;

    final nameFilter = _catalogNameFilter(studio, ['m.name_en', 'm.name_ja']);
    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT 
        COUNT(DISTINCT v.video_code) AS total
      FROM derived_video v
      WHERE 1=1
        AND v.maker_id IN (SELECT m.id FROM derived_maker m WHERE ${nameFilter.sql})
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...nameFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByStudio(
    String studio, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final nameFilter = _catalogNameFilter(studio, ['m.name_en', 'm.name_ja']);
    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v
        WHERE 1=1
          AND v.maker_id IN (SELECT m.id FROM derived_maker m WHERE ${nameFilter.sql})
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...nameFilter.args, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Director
  // ────────────────────────────────────────────────────────────────
  static Future<int> getCountAllVideosByDirector(String director, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;

    final nameFilter = _catalogNameFilter(director, ['d.name_romaji', 'd.name_kana', 'd.name_kanji']);
    final blacklist = _buildBlacklistClause();
    final maps = await _rawQuery('''
      SELECT 
        COUNT(DISTINCT v.video_code) AS total
      FROM derived_video_director vd
      JOIN derived_video v ON v.content_id = vd.content_id
      WHERE 1=1
        AND vd.director_id IN (SELECT d.id FROM derived_director d WHERE ${nameFilter.sql})
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...nameFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByDirector(
    String director, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final nameFilter = _catalogNameFilter(director, ['d.name_romaji', 'd.name_kana', 'd.name_kanji']);
    final blacklist = _buildBlacklistClause();
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v
        JOIN derived_video_director vd ON vd.content_id = v.content_id
        WHERE 1=1
          AND vd.director_id IN (SELECT d.id FROM derived_director d WHERE ${nameFilter.sql})
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...nameFilter.args, ...blacklist['args'], limit, offset]);
    return maps;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ Year
  // ────────────────────────────────────────────────────────────────
  static ({String sql, List<Object?> args}) _yearFilter(String year) {
    year = year.trim();
    if (!RegExp(r'^\d+$').hasMatch(year)) return (sql: 'v.release_date LIKE ?', args: ['$year%']);
    final next = '${year.substring(0, year.length - 1)}${String.fromCharCode(year.codeUnitAt(year.length - 1) + 1)}';
    return (sql: 'v.release_date >= ? AND v.release_date < ?', args: [year, next]);
  }

  static Future<int> getCountAllVideosByYear(String year, {ActressMode actressMode = ActressMode.all}) async {
    if (!_isReady()) return 0;

    final blacklist = _buildBlacklistClause();
    final yearFilter = _yearFilter(year);
    final maps = await _rawQuery('''
      SELECT 
        COUNT(DISTINCT v.video_code) AS total
      FROM derived_video v 
      WHERE 1=1
        AND ${yearFilter.sql}
        AND v.video_code IS NOT NULL
        ${blacklist['sql']}
        ${_actressModeClause(actressMode)}
    ''', [...yearFilter.args, ...blacklist['args']]);
    return maps[0]['total'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllVideosByYear(
    String year, {
    ActressMode actressMode = ActressMode.all,
    int page = 1,
    int perPage = 10000,
  }) async {
    if (!_isReady()) return [];

    final blacklist = _buildBlacklistClause();
    final yearFilter = _yearFilter(year);
    final limit = perPage;
    final offset = (page - 1) * limit;
    final maps = await _browseQuery('''
        SELECT
          v.rowid AS video_rowid,
          MAX(v.release_date) AS release_date
        FROM derived_video v
        WHERE 1=1
          AND ${yearFilter.sql}
          AND v.video_code IS NOT NULL
          ${blacklist['sql']}
          ${_actressModeClause(actressMode)}
        GROUP BY v.video_code
        ORDER BY
          v.release_date DESC, v.video_code
        LIMIT ? OFFSET ?
      ''', [...yearFilter.args, ...blacklist['args'], limit, offset]);
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
    int? yearEnd, int? durationMin, int? durationMax,
  }) async {
    if (!_isReady()) return [];

    final yM = DateTime.now().toStringEx(format: 'yyyy-MM');
    final dd = DateTime.now().toStringEx(format: 'dd');
    final limit = perPage ?? 100;
    final offset = ((page ?? 1) - 1) * limit;

    final filter = _buildFilterClause(
      correlatedRelations: true,
      videoCode: videoCode,
      actressName: actressName,
      categories: categories,
      yearStart: yearStart,
      yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax,
    );
    final blacklist = _buildBlacklistClause();

    final maps = await _catalogQuery('''
      v.video_code IS NOT NULL
      AND v.release_date IS NOT NULL
      AND v.runtime_mins IS NOT NULL
      AND v.label_id IS NOT NULL
      AND v.release_date >= ? AND v.release_date <= ?
      ${filter['sql']}
      ${blacklist['sql']}
  ''', ['$yM-01', '$yM-$dd', ...filter['args'], ...blacklist['args'], limit, offset]);

    return maps;
  }
}
