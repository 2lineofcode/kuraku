import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:javit/app/utils/chat_knowledge.dart';
import 'package:javit/app/utils/chat_service.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/sql_editor_smoke_test.dart /path/to/javit.db');
    exitCode = 1;
    return;
  }
  final api = ChatService();
  final token = CancelToken();
  try {
    final metadata = await Process.run('python3', ['-B', '-c', '''
import json, sqlite3, sys
from pathlib import Path
with sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True) as db:
    schema = {}
    for table, column in db.execute("SELECT s.name, c.name FROM sqlite_master s JOIN pragma_table_xinfo(s.name) c WHERE s.type IN ('table','view') ORDER BY s.name,c.cid"):
        schema.setdefault(table, []).append(column)
    print(json.dumps(schema))
''', args.single]);
    if (metadata.exitCode != 0) throw StateError('Could not read schema.');
    final schema = (jsonDecode(metadata.stdout as String) as Map).map((key, value) => MapEntry(key as String, (value as List).cast<String>()));
    final sql = await api.generateSql('Return the total number of rows in videos using SELECT COUNT(*) only.', schema, token)
        .timeout(const Duration(seconds: 90), onTimeout: () { token.cancel(); throw StateError('AI timed out.'); });
    final worker = ChatKnowledge(mainPath: args.single, loadScript: () => File('assets/sql_editor.py').readAsString());
    final validation = await worker.request({'sql': sql, 'operation': 'validate'}, token);
    if (validation['requires_confirmation'] != false) throw StateError('Smoke test expected a SELECT.');
    final result = await worker.request({'sql': sql}, token);
    if ((result['rows'] as List).length != 1 || result['write'] != false) throw StateError('Unexpected result.');
    stdout.writeln('SQL AI → validation → database execution OK (${schema.length} tables; ${(result['rows'] as List).length} result row).');
  } catch (error) {
    stderr.writeln(error is ChatException ? error.message : error is StateError ? error.message : 'SQL smoke test failed.');
    exitCode = 1;
  } finally {
    api.close();
  }
}
