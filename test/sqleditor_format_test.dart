import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/modules/home/page_sqleditor/page_sqleditor_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQL formatting preserves SQLite results, literals, comments and parameters', () async {
    final controller = PageSqleditorTab(sources: {'kuraku.db': '/kuraku.db'});
    addTearDown(controller.onClose);
    final statements = [
      "select release_date,dvd_id from derived_video dv where 1=1 and release_date is not null and dvd_id is not null and release_date like '%2026%' order by release_date desc limit 10",
      "with chosen as (select dvd_id from derived_video where release_date between '2026-01-01' and '2026-12-31') select * from chosen where dvd_id in (select dvd_id from derived_video)",
      "select 'it''s SELECT -- text' as title, :value, @value, \$value -- keep this comment\nfrom derived_video limit 1",
      'select "dvd_id", [release_date] from `derived_video` where dvd_id=:value',
      "select '{\"x\":1}' ->> '\$.x', '{\"x\":1}' -> '\$.x'",
      "select X'4142' as bytes, json_extract('{\"x\":1}', '\$.x'), 1e-3, -1, 0xFF",
    ];
    for (final sql in statements) {
      controller.input.text = sql;
      controller.formatQuery();
      expect(controller.queryError.value, isEmpty);
      final formatted = controller.input.text;
      controller.formatQuery();
      expect(controller.input.text, formatted, reason: 'Formatting must be idempotent');
      final result = await Process.run('python3', ['-B', '-c', '''
import json, sqlite3, sys
from contextlib import closing
with closing(sqlite3.connect(':memory:')) as db:
    db.execute('CREATE TABLE derived_video(release_date TEXT, dvd_id TEXT)')
    db.execute("INSERT INTO derived_video VALUES ('2026-05-26', 'KC90AE-309')")
    def execute(sql):
        return [[cell.hex() if isinstance(cell, bytes) else cell for cell in row] for row in db.execute(sql, {'value':'KC90AE-309'})]
    assert execute(sys.argv[1]) == execute(sys.argv[2]), (sys.argv[1], sys.argv[2])
''', sql, formatted]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n$formatted');
    }
    controller.input.text = statements.first;
    controller.formatQuery();
    expect(controller.input.text, contains('\n'));
    expect(controller.input.text, contains("'%2026%'"));
  });

  test('Format selection preserves surrounding SQL and selected whitespace', () {
    final controller = PageSqleditorTab(sources: {'kuraku.db': '/kuraku.db'});
    addTearDown(controller.onClose);
    const selection = ' select dvd_id from derived_video ';
    controller.input.value = const TextEditingValue(text: 'SELECT 1;\n$selection;\nSELECT 2;',
      selection: TextSelection(baseOffset: 10, extentOffset: 10 + selection.length));
    controller.formatQuery();
    expect(controller.input.text, startsWith('SELECT 1;\n '));
    expect(controller.input.text, endsWith(' ;\nSELECT 2;'));
    expect(controller.input.selection.textInside(controller.input.text), contains('\n'));
    controller.input.text = '  ';
    controller.formatQuery();
    expect(controller.input.text, '  ');
    controller.input.text = 'x' * 32001;
    controller.formatQuery();
    expect(controller.input.text.length, 32001);
    expect(controller.queryError.value, contains('32000'));
  });
}
