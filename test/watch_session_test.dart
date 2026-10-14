import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_watch_session.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/utils/watch_session_tracker.dart';
import 'package:sqflite/sqflite.dart';

class _Clock implements Stopwatch {
  @override
  bool isRunning = false;
  @override
  Duration elapsed = Duration.zero;
  @override
  void start() { isRunning = true; }
  @override
  void stop() { isRunning = false; }
  @override
  void reset() { elapsed = Duration.zero; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database, Transaction {
  final statements = <List<Object?>>[];
  final durations = <String, int>{};
  var total = 0;
  var failProfile = false;
  var days = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async { statements.add([sql, arguments ?? []]); }
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (table == 'profile') return [{'total_watch_duration': total}];
    final seconds = durations[whereArgs!.first];
    return seconds == null ? [] : [{'watched_seconds': seconds}];
  }
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await execute(sql, arguments);
    durations[arguments![0] as String] = arguments[3] as int;
    return 1;
  }
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    if (failProfile) throw StateError('Disk full');
    await execute(sql, arguments);
    total += arguments![0] as int;
    return 1;
  }
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    await execute('UPDATE $table SET ${values.keys.map((key) => '$key = ?').join(',')} WHERE $where', [...values.values, ...?whereArgs]);
    return 1;
  }
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => days.map((day) => <String, Object?>{'day': day}).toList();
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    final before = Map<String, int>.of(durations);
    final previousTotal = total;
    final offset = statements.length;
    try { return await action(this); } catch (_) {
      durations..clear()..addAll(before);
      total = previousTotal;
      statements.removeRange(offset, statements.length);
      rethrow;
    }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('Checkpoints are cumulative, retry-safe and split by video and midnight', () async {
    final clock = _Clock();
    var now = DateTime(2026, 9, 24, 23, 59, 58);
    final saved = <String, WatchSession>{};
    var fail = false;
    final tracker = WatchSessionTracker(now: () => now, stopwatch: clock, save: (sessions) async {
      if (fail) throw StateError('Disk full');
      for (final session in sessions) { saved[session.id] = session; }
    });
    tracker.setVideo(Videos(id: 'a', videoCode: 'A'));
    tracker.setPlaying(true);
    clock.elapsed = const Duration(seconds: 5);
    now = DateTime(2026, 9, 25, 0, 0, 3);
    await tracker.flush();
    expect(saved.values.map((s) => s.duration.inSeconds), [2, 3]);
    expect(saved.values.map((s) => s.startedAt.day), [24, 25]);
    clock.elapsed = const Duration(milliseconds: 600);
    tracker.setPlaying(false);
    await tracker.flush();
    now = now.add(const Duration(minutes: 10));
    tracker.setPlaying(true);
    clock.elapsed = const Duration(milliseconds: 400);
    fail = true;
    await expectLater(tracker.flush(), throwsStateError);
    fail = false;
    await tracker.flush();
    expect(saved.values.map((s) => s.duration.inSeconds), [2, 4]);
    // The tracker owns an immutable video identity even if the caller mutates its model.
    final video = Videos(id: 'b', videoCode: 'B');
    tracker.setVideo(video);
    video.id = 'wrong';
    tracker.setPlaying(true);
    clock.elapsed = const Duration(seconds: 7);
    await Future.wait([tracker.flush(), tracker.flush()]);
    await tracker.close();
    await tracker.close();
    expect(saved.values.map((s) => s.videoId), ['a', 'a', 'b']);
    expect(saved.values.map((s) => s.duration.inSeconds), [2, 4, 7]);
  });

  testWidgets('Periodic checkpoints and failed close retry without counting paused time', (tester) async {
    final clock = _Clock();
    var fail = false;
    final saved = <String, WatchSession>{};
    final tracker = WatchSessionTracker(stopwatch: clock, save: (sessions) async {
      if (fail) throw StateError('Offline');
      for (final session in sessions) { saved[session.id] = session; }
    });
    tracker.setVideo(Videos(id: 'video'));
    tracker.setPlaying(true);
    clock.elapsed = const Duration(seconds: 15);
    await tester.pump(const Duration(seconds: 15));
    expect(saved.values.single.duration.inSeconds, 15);
    clock.elapsed = const Duration(seconds: 2);
    fail = true;
    await expectLater(tracker.close(), throwsStateError);
    fail = false;
    await tester.pump(const Duration(seconds: 15));
    expect(saved.values.single.duration.inSeconds, 17);
    await tracker.close();
  });

  test('Exit flush includes all players and reset cannot resurrect pending history', () async {
    final saved = <String, WatchSession>{};
    final clocks = [_Clock(), _Clock()];
    var now = DateTime(2026, 9, 24, 12);
    final trackers = List.generate(2, (i) => WatchSessionTracker(now: () => now, stopwatch: clocks[i], save: (sessions) async {
      for (final session in sessions) { saved[session.id] = session; }
    }));
    for (var i = 0; i < trackers.length; i++) {
      trackers[i].setVideo(Videos(id: 'video-$i'));
      trackers[i].setPlaying(true);
      clocks[i].elapsed = Duration(seconds: 10 + i);
    }
    now = now.subtract(const Duration(hours: 1));
    await WatchSessionTracker.flushAll();
    expect(saved.values.map((s) => s.duration.inSeconds), [10, 11]);
    final gate = Completer<void>();
    final reset = WatchSessionTracker.resetHistory(() async { await gate.future; saved.clear(); });
    trackers.first.setPlaying(false);
    await WatchSessionTracker.flushAll();
    gate.complete();
    await reset;
    expect(saved, isEmpty);
    expect(clocks.first.isRunning, isFalse);
    expect(clocks.last.isRunning, isTrue);
    clocks.last.elapsed = const Duration(seconds: 3);
    await WatchSessionTracker.flushAll();
    expect(saved.values.single.duration.inSeconds, 3);
    expect(saved.values.single.videoId, 'video-1');
    for (final tracker in trackers) { await tracker.close(); }
    await WatchSessionTracker.flushAll();
  });

  test('Session persistence and profile updates are atomic, idempotent and preserve history', () async {
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    final migration = _Database();
    await DBUpdate.onUpgrade(migration, 11, 12);
    WatchSession session(String id, int seconds) => WatchSession(id: id, videoId: 'deleted-video', videoCode: 'CODE',
      startedAt: DateTime(2026, 9, 24), duration: Duration(seconds: seconds));
    await DBWatchSession.saveSessions([session('a', 10)]);
    await DBWatchSession.saveSessions([session('a', 10), session('a', 5)]);
    expect(db.total, 10);
    db.failProfile = true;
    await expectLater(DBWatchSession.saveSessions([session('a', 20), session('b', 7)]), throwsStateError);
    expect(db.total, 10);
    expect(db.durations, {'a': 10});
    db.failProfile = false;
    await DBWatchSession.saveSessions([session('a', 20), session('b', 7)]);
    expect(db.total, 27);
    final result = await Process.run('python3', ['-c', r'''
import json, sqlite3, sys
migration, writes = json.loads(sys.argv[1])
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE watch_session (id TEXT PRIMARY KEY, video_id TEXT, video_code TEXT, watched_seconds INTEGER, created_at TEXT)')
db.execute('CREATE TABLE profile (id TEXT PRIMARY KEY, total_watch_duration INTEGER, updated_at TEXT, badge_for_watch_duration TEXT)')
db.execute("INSERT INTO profile VALUES ('1', 99, NULL, NULL)")
db.execute("INSERT INTO watch_session VALUES ('legacy','deleted-video','OLD',5,'2020-01-01')")
for sql, args in migration: db.execute(sql, args)
assert db.execute('SELECT total_watch_duration FROM profile').fetchone()[0] == 5
assert db.execute('SELECT video_id FROM watch_session').fetchone()[0] == 'deleted-video'
for sql, args in writes: db.execute(sql, args)
assert db.execute('SELECT SUM(watched_seconds) FROM watch_session').fetchone()[0] == 32
assert db.execute('SELECT total_watch_duration FROM profile').fetchone()[0] == 32
assert db.execute('SELECT count(*) FROM watch_session').fetchone()[0] == 3
for seconds in [0, -1, None, 1.5]:
    try: db.execute("INSERT INTO watch_session VALUES ('invalid',NULL,NULL,?,'2026-09-24')", [seconds])
    except sqlite3.IntegrityError: pass
    else: raise AssertionError('Invalid duration accepted')
db.commit()
before = db.execute('SELECT * FROM watch_session').fetchall()
db.execute("CREATE TRIGGER fail_profile BEFORE UPDATE ON profile BEGIN SELECT RAISE(ABORT, 'failure'); END")
try:
    with db:
        for sql, args in writes: db.execute(sql, args)
except sqlite3.IntegrityError: pass
else: raise AssertionError('Failure not injected')
assert db.execute('SELECT * FROM watch_session').fetchall() == before
assert db.execute('SELECT total_watch_duration FROM profile').fetchone()[0] == 32
legacy = sqlite3.connect(':memory:')
legacy.execute('CREATE TABLE watch_session (id TEXT PRIMARY KEY, video_id TEXT, video_code TEXT, watched_seconds INTEGER, created_at TEXT)')
legacy.execute("INSERT INTO watch_session VALUES ('invalid',NULL,NULL,-1,'2026-09-24')")
legacy.commit()
try:
    legacy.execute('BEGIN')
    for sql, args in migration: legacy.execute(sql, args)
except sqlite3.IntegrityError:
    legacy.rollback()
else: raise AssertionError('Invalid legacy history accepted')
assert legacy.execute('SELECT watched_seconds FROM watch_session').fetchone()[0] == -1
assert not legacy.execute("SELECT name FROM sqlite_master WHERE name='watch_session_new'").fetchall()
''', jsonEncode([migration.statements, db.statements])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('Streak includes yesterday until today ends and stops at a missing day', () async {
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    final today = DateTime(2026, 9, 24);
    db.days = ['2026-09-24', '2026-09-23', '2026-09-22'];
    expect(await DBWatchSession.getCurrentStreakDays(now: today), 3);
    db.days = ['2026-09-23', '2026-09-22', '2026-09-20'];
    expect(await DBWatchSession.getCurrentStreakDays(now: today), 2);
    db.days = ['2026-09-22'];
    expect(await DBWatchSession.getCurrentStreakDays(now: today), 0);
    db.days = [];
    expect(await DBWatchSession.getCurrentStreakDays(now: today), 0);
  });
}
