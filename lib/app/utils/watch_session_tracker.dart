import 'dart:async';

import 'package:uuid/v4.dart';

import '../core/app_logging.dart';
import '../data/database/db_watch_session.dart';
import '../data/models/videos_entity.dart';

class WatchSessionTracker {
  static final _active = <WatchSessionTracker>{};

  static Future<void> flushAll() async {
    await Future.wait(_active.toList().map((tracker) => tracker.flush()));
  }

  static Future<void> resetHistory(Future<void> Function() clearHistory) async {
    final trackers = _active.toList();
    for (final tracker in trackers) {
      tracker._capture();
      tracker._resetting = true;
      tracker._resumeAfterReset = tracker._clock.isRunning;
      tracker._clock.stop();
    }
    try {
      await Future.wait(trackers.map((tracker) => tracker._writes));
      await clearHistory();
      for (final tracker in trackers) {
        tracker._pending.clear();
        tracker._current = null;
      }
    } finally {
      for (final tracker in trackers) {
        tracker._resetting = false;
        tracker.setPlaying(tracker._resumeAfterReset);
      }
    }
  }

  WatchSessionTracker({DateTime Function()? now, Stopwatch? stopwatch, Future<void> Function(List<WatchSession>)? save})
      : _now = now ?? DateTime.now, _clock = stopwatch ?? Stopwatch(), _save = save ?? DBWatchSession.saveSessions;

  final DateTime Function() _now;
  final Stopwatch _clock;
  final Future<void> Function(List<WatchSession>) _save;
  final _pending = <String, WatchSession>{};
  Future<void> _writes = Future<void>.value();
  Timer? _timer;
  DateTime? _startedAt;
  WatchSession? _current;
  String? _videoId;
  String? _videoCode;
  bool _hasVideo = false;
  bool _closed = false;
  bool _resetting = false;
  bool _resumeAfterReset = false;

  void setVideo(Videos video) {
    if (_closed) throw StateError('Watch tracker is closed');
    _active.add(this);
    setPlaying(false);
    _current = null;
    _videoId = video.id;
    _videoCode = video.videoCode;
    _hasVideo = true;
  }

  void setPlaying(bool playing) {
    if (_closed || !_hasVideo) return;
    if (_resetting) { _resumeAfterReset = playing; return; }
    if (playing) {
      if (_clock.isRunning) return;
      _startedAt = _now();
      _clock..reset()..start();
      _ensureTimer();
    } else {
      _capture();
      _clock.stop();
      unawaited(flush().catchError(_logError));
    }
  }

  void _capture() {
    if (!_clock.isRunning) return;
    var start = _startedAt!;
    final end = start.add(_clock.elapsed);
    _clock.reset();
    _startedAt = _now();
    while (start.isBefore(end)) {
      final midnight = DateTime(start.year, start.month, start.day + 1);
      final until = end.isBefore(midnight) ? end : midnight;
      final current = _current;
      final sameDay = current != null && current.startedAt.year == start.year && current.startedAt.month == start.month && current.startedAt.day == start.day;
      final session = WatchSession(
        id: sameDay ? current.id : const UuidV4().generate(),
        videoId: _videoId, videoCode: _videoCode,
        startedAt: sameDay ? current.startedAt : start,
        duration: (sameDay ? current.duration : Duration.zero) + until.difference(start),
      );
      _current = session;
      _pending[session.id] = session;
      start = until;
    }
  }

  Future<void> flush() {
    if (_resetting) return _writes;
    _capture();
    final snapshot = _pending.values.where((session) => session.duration.inSeconds > 0).toList();
    final result = _writes.then((_) async {
      if (snapshot.isNotEmpty) await _save(snapshot);
      for (final session in snapshot) {
        if (identical(_pending[session.id], session)) _pending.remove(session.id);
      }
      if (!_clock.isRunning && !_pending.values.any((session) => session.duration.inSeconds > 0)) {
        _timer?.cancel();
        _timer = null;
        if (_closed) _active.remove(this);
      }
    });
    _writes = result.catchError((Object _) {});
    return result;
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => unawaited(flush().catchError(_logError)));
  }

  Future<void> close() async {
    if (!_closed) {
      _capture();
      _clock.stop();
      _closed = true;
    }
    try {
      await flush();
    } catch (_) {
      // Keep failed checkpoints available for retry while the app is still running.
      _ensureTimer();
      rethrow;
    }
  }

  void _logError(Object error) => AppLog.logW('Watch session checkpoint failed: $error');
}
