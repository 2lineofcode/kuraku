import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/core/app_logging.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';

void main() {
  setUp(HomePanelAppLog.clear);
  tearDownAll(HomePanelAppLog.clear);

  test('enabled app logs also reach terminal output with their level', () {
    final lines = <String>[];
    runZoned(() {
      AppLog.logD('debug line');
      AppLog.logI('info line');
      AppLog.logW('warning line');
      AppLog.logE('error line');
      AppLog.logS('success line');
    }, zoneSpecification: ZoneSpecification(print: (_, _, _, line) => lines.add(line)));

    expect(lines, HomePanelAppLog.appLogRuntime.reversed.map((entry) => '[${entry.type}] ${entry.content}').toList());
    expect(lines, contains('[ERROR] error line'));
    expect(lines, contains('[OK] success line'));
  });

  test('errors and successes are always pushed to the runtime log panel', () {
    AppLog.logE('Database is gone');
    AppLog.logS('Library scanned');

    final entries = HomePanelAppLog.appLogRuntime;
    expect(entries, hasLength(2));
    expect(entries.first.type, 'OK', reason: 'the newest entry is inserted first');
    expect(entries.first.content, 'Library scanned');
    expect(entries.last.type, 'ERROR');
    expect(entries.last.content, 'Database is gone');
    expect(entries.every((entry) => (entry.createdAt ?? '').isNotEmpty), isTrue);
  });

  test('non string payloads are stored through their string representation', () {
    AppLog.logE({'code': 'ABP-001', 'retry': 2});
    AppLog.logS(42);

    expect(HomePanelAppLog.appLogRuntime.last.content, contains('ABP-001'));
    expect(HomePanelAppLog.appLogRuntime.first.content, '42');
  });

  test('the panel keeps only the entries produced by the enabled log levels', () {
    AppLog.logD('debug line');
    AppLog.logI('info line');
    AppLog.logW('warning line');
    AppLog.logE('error line');

    final types = HomePanelAppLog.appLogRuntime.map((entry) => entry.type).toList();
    expect(types, contains('ERROR'), reason: 'errors are logged at every level');
    expect(types.toSet(), hasLength(types.length), reason: 'each level is written at most once');
    expect(types, isNot(contains('OK')));
    for (final type in types) {
      expect(['DEBUG', 'INFO', 'WARNING', 'ERROR'], contains(type));
    }
  });

  test('clear empties the panel', () {
    AppLog.logE('one');
    AppLog.logE('two');
    expect(HomePanelAppLog.appLogRuntime, hasLength(2));

    HomePanelAppLog.clear();
    expect(HomePanelAppLog.appLogRuntime, isEmpty);
  });

  test('log entries serialise to the database column names and back', () {
    final entry = AppLogRuntime(id: 'log-1', type: 'ERROR', content: 'boom', createdAt: '2026-03-04 10:00:00');
    expect(entry.toJson(), {'id': 'log-1', 'type': 'ERROR', 'content': 'boom', 'created_at': '2026-03-04 10:00:00'});

    final restored = AppLogRuntime.fromJson(Map<String, dynamic>.from(jsonDecode('$entry')));
    expect(restored.toJson(), entry.toJson());
    expect(AppLogRuntime.fromJson({}).toJson().values.every((value) => value == null), isTrue);
  });

  test('log levels are ordered from the most to the least severe', () {
    expect(LogLevel.values, [LogLevel.error, LogLevel.warn, LogLevel.info, LogLevel.debug]);
    expect(LogLevel.error.index, lessThan(LogLevel.debug.index));
  });
}
