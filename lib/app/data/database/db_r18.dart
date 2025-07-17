import 'package:get/get.dart';

import 'db_init.dart';

mixin DBR18 {
  static final _db = Get.find<DBService>().dbR18;

  static Future<Map<String, dynamic>?> getVideo(String code) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
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
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
        SELECT DISTINCT a.*
        FROM derived_video_actress va
        JOIN derived_video v ON v.content_id = va.content_id
        JOIN derived_actress a ON a.id = va.actress_id
        WHERE v.dvd_id = ?;
      ''', [code]);

    return maps;
  }

  static Future<List<Map<String, dynamic>>> getCategory(String code) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
        SELECT DISTINCT  cat.id, cat.name_en as category
        FROM derived_video_category c 
        JOIN derived_video v ON v.content_id = c.content_id
        JOIN derived_category cat ON cat.id = c.category_id
        WHERE v.dvd_id = ? AND cat.name_en NOT NULL;
      ''', [code]);

    return maps;
  }

  static Future<Map<String, dynamic>?> getDirector(String code) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
        SELECT DISTINCT d.*
        FROM derived_video_director vd
        JOIN derived_video v ON v.content_id = vd.content_id
        JOIN derived_director d ON d.id = vd.director_id
        WHERE v.dvd_id = ?;
      ''', [code]);

    return maps.isNotEmpty ? maps[0] : null;
  }
}
