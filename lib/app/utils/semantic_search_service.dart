import 'dart:async';

import 'package:get/get.dart';

import '../data/models/videos_entity.dart';
import 'local_semantic_worker.dart';

class SemanticSearchHit {
  final Videos video;
  final double score;
  final String reason;

  SemanticSearchHit({required this.video, required this.score, this.reason = 'Metadata'});
}

class SemanticIndexProgress {
  final int current, total, indexed, skipped;
  final bool paused, cancelled;
  final String message;
  const SemanticIndexProgress({this.current = 0, this.total = 0, this.indexed = 0,
    this.skipped = 0, this.paused = false, this.cancelled = false, this.message = ''});
}

mixin SemanticSearchService {
  static String get modelName => LocalSemanticWorker.modelName;
  static bool indexing = false;
  static final _indexOwner = Object();
  static bool _cancelled = false;
  static int _players = 0;
  static int _playbackRevision = 0;
  static Completer<void>? _playbackFinished;
  static bool get playbackActive => _players > 0;

  static void beginPlayback() {
    LocalSemanticWorker.cancelSetup();
    _players++;
    _playbackRevision++;
    _playbackFinished ??= Completer<void>();
    LocalSemanticWorker.stop();
  }

  static void endPlayback() {
    if (_players > 0) _players--;
    if (_players == 0) {
      _playbackFinished?.complete();
      _playbackFinished = null;
    }
  }

  static void cancelIndex() {
    _cancelled = true;
    LocalSemanticWorker.cancelRequests(_indexOwner);
    LocalSemanticWorker.interruptIndex();
  }

  static Future<Map<String, dynamic>> indexStatus() async {
    if (playbackActive) throw SemanticSearchException('Visual indexing pauses while a player is open.'.tr);
    return Map<String, dynamic>.from(await LocalSemanticWorker.request('summary'));
  }

  static Future<SemanticIndexProgress> reindexMissing({Future<void> Function(SemanticIndexProgress)? onProgress}) => _index(false, onProgress);
  static Future<SemanticIndexProgress> reindexAll({Future<void> Function(SemanticIndexProgress)? onProgress}) => _index(true, onProgress);

  static Future<SemanticIndexProgress> _index(bool force, Future<void> Function(SemanticIndexProgress)? onProgress) async {
    if (indexing) throw SemanticSearchException('Visual indexing is already running.'.tr);
    indexing = true;
    _cancelled = false;
    var processed = 0, skipped = 0, current = 0, total = 0;
    var lastIssue = '';
    SemanticIndexProgress progress({bool paused = false}) => SemanticIndexProgress(
      current: current, total: total, indexed: processed, skipped: skipped,
      paused: paused, cancelled: _cancelled, message: lastIssue,
    );
    Future<void> waitForPlayback() async {
      while (playbackActive && !_cancelled) {
        final resumed = _playbackFinished!.future;
        await onProgress?.call(progress(paused: true));
        await Future.any([resumed, Future<void>.delayed(const Duration(seconds: 1))]);
      }
    }
    try {
      Map<String, dynamic> plan;
      while (true) {
        await waitForPlayback();
        if (_cancelled) return progress();
        final revision = _playbackRevision;
        try {
          plan = Map<String, dynamic>.from(await LocalSemanticWorker.request('plan', {'force': force}, _indexOwner));
          break;
        } catch (_) {
          if (_cancelled) return progress();
          if (revision == _playbackRevision) rethrow;
        }
      }
      final ids = List<String>.from(plan['ids']);
      total = ids.length;
      await onProgress?.call(progress());
      for (var i = 0; i < ids.length && !_cancelled; i++) {
        await waitForPlayback();
        if (_cancelled) break;
        final revision = _playbackRevision;
        try {
          final result = await LocalSemanticWorker.request('index', {'video_id': ids[i], 'force': force}, _indexOwner);
          if (result['indexed'] == true) { processed++; } else { skipped++; }
          if (result['error'] != null) lastIssue = result['error'].toString();
          current = i + 1;
          await onProgress?.call(progress());
        } catch (_) {
          if (_cancelled) break;
          if (!playbackActive && revision == _playbackRevision) rethrow;
          i--;
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return progress();
    } finally {
      if (!_cancelled && !playbackActive) {
        try { await LocalSemanticWorker.request('unload'); } catch (_) {}
      }
      indexing = false;
    }
  }

  static Future<List<SemanticSearchHit>> search(String query, {int? limit, Object? owner, double minimum = .24, void Function(int indexed, int total)? onCoverage}) async {
    if (query.trim().isEmpty) return [];
    if (playbackActive) throw SemanticSearchException('Close the player to use Visual Search.'.tr);
    final result = await LocalSemanticWorker.request('search', {'query': query, 'minimum': minimum}, owner);
    onCoverage?.call(result['indexed'] as int, result['total'] as int);
    final hits = (result['hits'] as List).map((item) => SemanticSearchHit(
      video: Videos.fromJson(Map<String, dynamic>.from(item['video'])),
      score: (item['score'] as num).toDouble(),
      reason: item['reason']?.toString() ?? 'Metadata',
    )).toList();
    return limit == null ? hits : hits.take(limit < 0 ? 0 : limit).toList();
  }
}
