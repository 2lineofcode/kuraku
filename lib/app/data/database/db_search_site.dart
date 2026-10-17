import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../models/search_site.dart';
import '_init_db.dart';

class DBSearchSite {
  static final sites = SearchSite.defaults.toList().obs;
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> load([Database? db]) async {
    final rows = await (db ?? _db).query('search_site', orderBy: 'rowid');
    sites.assignAll(rows.map(SearchSite.fromJson));
  }

  static SearchSite resolve(String name) => sites.firstWhere((site) => site.name == name,
    orElse: () => sites.firstWhere((site) => site.name.toLowerCase() == name.toLowerCase(), orElse: () => sites.first));

  static Future<void> save(SearchSite site, {bool update = false}) async {
    site.validate();
    if (update) {
      final count = await _db.update('search_site', {'search_url': site.searchUrl, 'download_url': site.downloadUrl}, where: 'name = ? COLLATE NOCASE', whereArgs: [site.name]);
      if (count != 1) throw StateError('Search site no longer exists.');
    } else {
      await _db.insert('search_site', site.toJson());
    }
    await load();
  }

  static Future<void> remove(SearchSite site) async {
    if (site.isDefault) throw StateError('Default sites cannot be deleted.');
    await _db.delete('search_site', where: 'name = ? COLLATE NOCASE', whereArgs: [site.name]);
    await load();
  }
}
