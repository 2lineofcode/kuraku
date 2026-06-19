import 'dart:math' as math;

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/app_setting.dart';
import '../data/database/db_video_embedding.dart';
import '../data/database/db_videos.dart';
import '../data/models/videos_entity.dart';
import 'helper.dart';
import 'local_semantic_worker.dart';

class SemanticSearchHit {
  final Videos video;
  final double score;

  SemanticSearchHit({
    required this.video,
    required this.score,
  });
}

mixin SemanticSearchService {
  static const _vectorSize = 384;
  static const _modelName = 'local-hash-v2';

  static const Map<String, List<String>> _synonyms = {
    'indo': ['indonesia', 'subtitle', 'sub', 'id'],
    'indonesia': ['indo', 'subtitle', 'sub', 'id'],
    'english': ['eng', 'subtitle', 'sub', 'en'],
    'eng': ['english', 'subtitle', 'sub', 'en'],
    'subtitle': ['sub', 'captions'],
    'uncensored': ['reducing', 'mosaic', 'rm', 'un'],
    'censored': ['mosaic'],
    'outdoor': ['outside', 'nature', 'park', 'beach'],
    'outside': ['outdoor', 'nature'],
    'teacher': ['school', 'class', 'uniform'],
    'office': ['secretary', 'boss', 'work'],
    'short': ['quick', 'brief'],
    'long': ['full', 'extended'],
    'romance': ['romantic', 'soft', 'love'],
    'soft': ['gentle', 'romance', 'romantic'],
    'hardcore': ['intense', 'rough'],
    'rough': ['hardcore', 'intense'],
    'nonjav': ['non', 'jav'],
    'jav': ['japanese', 'code'],
  };

  static String get modelName => _modelName;

  static String buildDocumentText(Videos video) {
    return buildDocumentTextWithVisual(video, '');
  }

  static String buildDocumentTextWithVisual(Videos video, String visualTags) {
    final actresses = (video.actress ?? [])
        .map((item) => (item.nameRomaji ?? '').trim())
        .where((item) => item.isNotEmpty)
        .join(', ');

    final categories = (video.category ?? [])
        .map((item) => (item.category ?? '').trim())
        .where((item) => item.isNotEmpty)
        .join(', ');

    final path = video.videoPath ?? '';
    final quality = (video.quality ?? '').trim();
    final durationMinutes = (video.duration ?? 0).toInt();
    final durationTag = _durationTag(durationMinutes);
    final qualityTag = _qualityTag(quality);

    final flags = <String>[
      (video.videoCode ?? '').isNotEmpty ? 'jav japanese coded' : 'non jav uncoded',
      (video.videoPath ?? '').isHasIdSub() ? 'subtitle indonesia indo id sub' : '',
      (video.videoPath ?? '').isHasEnSub() ? 'subtitle english eng en sub' : '',
      (video.videoPath ?? '').isHasUncensored() ? 'uncensored reducing mosaic rm un' : '',
      qualityTag,
      durationTag,
    ].where((item) => item.isNotEmpty).join(' | ');

    final parentFolder = path.isEmpty ? '' : p.basename(p.dirname(path));
    final fileName = path.isEmpty ? '' : p.basenameWithoutExtension(path);

    final title = (video.title ?? '').trim();
    final code = (video.videoCode ?? '').trim();

    return [
      'title: ${title.isEmpty ? 'none' : '$title | $title'}',
      'code: ${code.isEmpty ? 'none' : '$code | $code'}',
      'title_ja: ${video.titleJa ?? 'none'}',
      'actress: ${actresses.isEmpty ? 'none' : '$actresses | $actresses'}',
      'category: ${categories.isEmpty ? 'none' : '$categories | $categories'}',
      'series: ${video.series ?? 'none'}',
      'studio: ${video.studio ?? 'none'}',
      'label: ${video.label ?? 'none'}',
      'director: ${video.director ?? 'none'}',
      'release_date: ${video.releaseDate ?? 'none'}',
      'duration_minutes: $durationMinutes',
      'quality: ${quality.isEmpty ? 'none' : quality}',
      'flags: ${flags.isEmpty ? 'none' : flags}',
      'visual: ${visualTags.trim().isEmpty ? 'none' : visualTags.trim()}',
      'folder: ${parentFolder.isEmpty ? 'none' : '$parentFolder | $parentFolder'}',
      'file_name: ${fileName.isEmpty ? 'none' : '$fileName | $fileName'}',
      'path: ${path.isEmpty ? 'none' : path}',
    ].join(' | ');
  }

  static String buildQueryText(String query) {
    return query.trim();
  }

  static Future<int> getMissingEmbeddingCount() async {
    final videos = await DBVideos.getAll();
    if (videos.isEmpty) return 0;
    final records = await DBVideoEmbeddings.getAll();
    final recordMap = <String, VideoEmbeddingRecord>{};
    for (final record in records) {
      recordMap[record.videoId] = record;
    }

    var missing = 0;
    for (final video in videos) {
      final videoId = (video.id ?? '').trim();
      if (videoId.isEmpty) continue;

      final record = recordMap[videoId];
      final sourceText = _baseDocumentText(video);
      if (record == null || record.model != _modelName || _normalizeSourceForChangeCheck(record.sourceText) != _normalizeSourceForChangeCheck(sourceText)) {
        missing++;
      }
    }
    return missing;
  }

  static Future<int> reindexMissing({Future<void> Function(int current, int total, Videos video)? onProgress}) async {
    final videos = await DBVideos.getAll(orderBy: 'updated_at DESC');
    final records = await DBVideoEmbeddings.getAll();
    final recordMap = <String, VideoEmbeddingRecord>{};
    for (final record in records) {
      recordMap[record.videoId] = record;
    }

    final pending = <Videos>[];
    for (final video in videos) {
      final videoId = (video.id ?? '').trim();
      if (videoId.isEmpty) continue;

      final sourceText = _baseDocumentText(video);
      final record = recordMap[videoId];
      if (record == null || record.model != _modelName || _normalizeSourceForChangeCheck(record.sourceText) != _normalizeSourceForChangeCheck(sourceText)) {
        pending.add(video);
      }
    }

    return _indexVideos(pending, onProgress: onProgress);
  }

  static Future<int> reindexAll({Future<void> Function(int current, int total, Videos video)? onProgress}) async {
    final videos = await DBVideos.getAll(orderBy: 'updated_at DESC');
    return _indexVideos(videos, onProgress: onProgress);
  }

  static Future<int> _indexVideos(
    List<Videos> videos, {
    Future<void> Function(int current, int total, Videos video)? onProgress,
  }) async {
    var processed = 0;
    final total = videos.length;
    final visualTagsMap = await _resolveVisualTags(videos);
    for (var i = 0; i < total; i++) {
      final video = videos[i];
      final videoId = (video.id ?? '').trim();
      if (videoId.isEmpty) continue;

      final sourceText = buildDocumentTextWithVisual(video, visualTagsMap[videoId] ?? '');
      final embedding = _vectorize(sourceText, isQuery: false);
      await DBVideoEmbeddings.upsert(
        videoId: videoId,
        sourceText: sourceText,
        embedding: embedding,
        model: _modelName,
      );
      processed++;
      if (onProgress != null) {
        await onProgress(processed, total, video);
      }
    }
    return processed;
  }

  static Future<Map<String, String>> _resolveVisualTags(List<Videos> videos) async {
    final imagePathToVideoId = <String, String>{};
    for (final video in videos) {
      final videoId = (video.id ?? '').trim();
      if (videoId.isEmpty) continue;
      final thumbPath = _thumbPathForVideo(video.videoPath ?? '');
      if (thumbPath == null) continue;
      imagePathToVideoId[thumbPath] = videoId;
    }

    if (imagePathToVideoId.isEmpty) return <String, String>{};

    final raw = await LocalSemanticWorker.extractVisualTags(imagePathToVideoId.keys.toList());
    final result = <String, String>{};
    raw.forEach((imagePath, tags) {
      final videoId = imagePathToVideoId[imagePath];
      if (videoId != null) {
        result[videoId] = tags;
      }
    });
    return result;
  }

  static String _baseDocumentText(Videos video) {
    return buildDocumentTextWithVisual(video, '');
  }

  static String _normalizeSourceForChangeCheck(String value) {
    return value.replaceAll(RegExp(r'visual:\s*[^|]*'), 'visual:');
  }

  static String? _thumbPathForVideo(String videoPath) {
    if (videoPath.trim().isEmpty) return null;
    final appPath = Get.find<AppSettingService>().appPath;
    return p.join(appPath, 'vid_thumbnail', '${p.basenameWithoutExtension(videoPath)}.jpg');
  }

  static Future<List<SemanticSearchHit>> search(String query, {int limit = 80}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <SemanticSearchHit>[];

    final records = await DBVideoEmbeddings.getAll();
    if (records.isEmpty) return <SemanticSearchHit>[];

    final queryEmbedding = _vectorize(buildQueryText(trimmed), isQuery: true);
    final videos = await DBVideos.getAll();
    final videoMap = <String, Videos>{};
    for (final video in videos) {
      final videoId = (video.id ?? '').trim();
      if (videoId.isNotEmpty) {
        videoMap[videoId] = video;
      }
    }

    final tokens = _normalizeTokens(trimmed, includeSynonyms: true);
    final hits = <SemanticSearchHit>[];

    for (final record in records) {
      final video = videoMap[record.videoId];
      if (video == null) continue;

      final semanticScore = _cosineSimilarity(queryEmbedding, record.embedding);
      final keywordBoost = _keywordOverlap(tokens, record.sourceText);
      final exactBoost = _exactIntentBoost(tokens, video);
      final finalScore = semanticScore + (keywordBoost * 0.18) + exactBoost;
      if (finalScore < 0.12) continue;

      hits.add(SemanticSearchHit(video: video, score: finalScore));
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    if (hits.length <= limit) return hits;
    return hits.sublist(0, limit);
  }

  static List<double> _vectorize(String input, {required bool isQuery}) {
    final weights = <String, double>{};
    final tokens = _normalizeTokens(input, includeSynonyms: isQuery);

    for (final token in tokens) {
      weights[token] = (weights[token] ?? 0) + 1.0;
      if (token.length >= 5) {
        for (final trigram in _charNgrams(token, 3)) {
          weights['tri:$trigram'] = (weights['tri:$trigram'] ?? 0) + 0.35;
        }
      }
    }

    if (isQuery) {
      for (final token in tokens) {
        final synonyms = _synonyms[token];
        if (synonyms == null) continue;
        for (final synonym in synonyms) {
          weights[synonym] = (weights[synonym] ?? 0) + 0.8;
        }
      }
    }

    final vector = List<double>.filled(_vectorSize, 0);
    weights.forEach((token, weight) {
      final hash = _stableHash(token);
      final index = hash.abs() % _vectorSize;
      final sign = hash.isEven ? 1.0 : -1.0;
      vector[index] += weight * sign;
    });

    return _normalizeVector(vector);
  }

  static List<String> _normalizeTokens(String input, {bool includeSynonyms = false}) {
    final base = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((item) => item.trim().length >= 2)
        .toList();

    if (includeSynonyms == false) return base;

    final expanded = <String>[...base];
    for (final token in base) {
      final synonyms = _synonyms[token];
      if (synonyms != null) expanded.addAll(synonyms);
    }
    return expanded;
  }

  static double _keywordOverlap(List<String> queryTokens, String sourceText) {
    if (queryTokens.isEmpty) return 0;
    final source = sourceText.toLowerCase();
    var matched = 0;
    for (final token in queryTokens.toSet()) {
      if (source.contains(token)) matched++;
    }
    return matched / queryTokens.toSet().length;
  }

  static double _exactIntentBoost(List<String> queryTokens, Videos video) {
    if (queryTokens.isEmpty) return 0;
    final code = (video.videoCode ?? '').toLowerCase();
    final title = (video.title ?? '').toLowerCase();
    final path = (video.videoPath ?? '').toLowerCase();
    var score = 0.0;

    for (final token in queryTokens.toSet()) {
      if (code.contains(token)) score += 0.08;
      if (title.contains(token)) score += 0.05;
      if (path.contains(token)) score += 0.03;
    }

    return score.clamp(0, 0.25);
  }

  static List<String> _charNgrams(String token, int n) {
    if (token.length < n) return <String>[token];
    final values = <String>[];
    for (var i = 0; i <= token.length - n; i++) {
      values.add(token.substring(i, i + n));
    }
    return values;
  }

  static int _stableHash(String input) {
    var hash = 2166136261;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash *= 16777619;
      hash &= 0x7fffffff;
    }
    return hash;
  }

  static List<double> _normalizeVector(List<double> values) {
    var norm = 0.0;
    for (final value in values) {
      norm += value * value;
    }
    if (norm == 0) return values;

    final scale = math.sqrt(norm);
    return values.map((value) => value / scale).toList();
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;

    var dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  static String _durationTag(int durationMinutes) {
    if (durationMinutes <= 0) return '';
    if (durationMinutes <= 60) return 'duration short brief quick';
    if (durationMinutes <= 120) return 'duration medium standard';
    return 'duration long extended full';
  }

  static String _qualityTag(String quality) {
    if (quality.isEmpty) return '';
    final value = quality.toLowerCase();
    if (value.contains('3840x2160') || value.contains('4k')) return 'quality 4k ultra hd high resolution';
    if (value.contains('1920x1080')) return 'quality fhd full hd high resolution';
    if (value.contains('1280x720')) return 'quality hd medium resolution';
    return 'quality $quality';
  }
}
