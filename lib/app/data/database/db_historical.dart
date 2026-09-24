import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '_init_db.dart';

const kHistoricalTypeDownload = 'download';
const kHistoricalTypeSearch = 'search';

mixin DBHistorical {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> save(String type, String query) async {
    final value = query.trim();
    if (type.isEmpty || value.isEmpty) return;
    await _db.rawInsert('''
      INSERT INTO historical (type, query, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(type, query) DO UPDATE SET query = excluded.query, updated_at = excluded.updated_at
    ''', [type, value, DateTime.now().microsecondsSinceEpoch]);
  }

  static Future<List<String>> search(String type, String query) async {
    final rows = await _db.query('historical', columns: ['query'],
      where: 'type = ? AND instr(lower(query), lower(?)) > 0',
      whereArgs: [type, query.trim()], orderBy: 'updated_at DESC, id DESC', limit: 8);
    return rows.map((row) => row['query'] as String).toList();
  }

  static Future<void> clear(String type) async {
    await _db.delete('historical', where: 'type = ?', whereArgs: [type]);
  }

  static Future<void> delete(String type, String query) async {
    await _db.delete('historical', where: 'type = ? AND query = ?', whereArgs: [type, query]);
  }
}
