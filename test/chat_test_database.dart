import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:sqflite/sqflite.dart';

class ChatTestPreferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ChatTestService extends DBService {
  @override
  Future<void> onReady() async {}
}

class ChatTestDatabase implements Database, Transaction {
  final rows = <String, List<Map<String, Object?>>>{'chat_conversation': [], 'chat_message': [], 'chat_translation': []};
  final schema = <String>[];
  final statements = <List<Object?>>[];
  bool failWrites = false;
  bool failMessageInsert = false;
  bool failConversationUpdate = false;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async { schema.add(sql); }
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    final found = rows[table]!.where((row) => where == null || List.generate(where.split(' AND ').length, (i) => row[where.split(' AND ')[i].split(' ').first] == whereArgs![i]).every((matches) => matches)).map((row) => Map<String, Object?>.from(row)).toList();
    if (table == 'chat_message') {
      found.sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    } else if (table == 'chat_conversation') {
      found.sort((a, b) {
        final pinned = ((b['is_pinned'] as int?) ?? 0).compareTo((a['is_pinned'] as int?) ?? 0);
        return pinned != 0 ? pinned : (b['last_activity_at'] as String).compareTo(a['last_activity_at'] as String);
      });
    }
    return found;
  }
  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (failWrites || (table == 'chat_message' && failMessageInsert)) throw StateError('Disk full');
    if (table == 'chat_translation' && conflictAlgorithm == ConflictAlgorithm.replace) rows[table]!.removeWhere((row) => row['source_text'] == values['source_text'] && row['target_language'] == values['target_language']);
    statements.add(['${conflictAlgorithm == ConflictAlgorithm.replace ? 'INSERT OR REPLACE' : 'INSERT'} INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})', values.values.toList()]);
    rows[table]!.add(Map.of(values));
    return 1;
  }
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    if (failWrites || table == 'chat_conversation' && failConversationUpdate) throw StateError('Disk full');
    statements.add(['UPDATE $table SET ${values.keys.map((key) => '$key = ?').join(',')} WHERE $where', [...values.values, ...?whereArgs]]);
    final found = rows[table]!.where((row) => row['id'] == whereArgs?.first).toList();
    for (final row in found) { row.addAll(values); }
    return found.length;
  }
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    if (failWrites) throw StateError('Disk full');
    statements.add(['DELETE FROM $table WHERE $where', whereArgs]);
    rows[table]!.removeWhere((row) => row[where!.split(' ').first] == whereArgs!.first
        && (where != 'conversation_id = ? AND position > ?' || (row['position'] as int) > (whereArgs[1] as int)));
    if (table == 'chat_conversation') rows['chat_message']!.removeWhere((row) => row['conversation_id'] == whereArgs!.first);
    return 1;
  }
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql == 'PRAGMA table_info(chat_message)') return schema.any((sql) => sql.contains('ADD COLUMN activity')) ? [{'name': 'activity'}] : [];
    final messages = rows['chat_message']!.where((row) => row['conversation_id'] == arguments!.first);
    final last = messages.fold<int>(0, (n, row) => (row['position'] as int) > n ? row['position'] as int : n);
    return [{'position': last + 1}];
  }
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    final snapshot = rows.map((key, value) => MapEntry(key, value.map((row) => Map<String, Object?>.of(row)).toList()));
    final start = statements.length;
    try {
      return await action(this);
    } catch (_) {
      rows..clear()..addAll(snapshot);
      statements.removeRange(start, statements.length);
      rethrow;
    }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
