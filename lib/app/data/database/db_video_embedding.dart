import 'dart:convert';
import 'dart:typed_data';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_pref.dart';
import '_init_db.dart';

class VideoEmbeddingRecord {
  String videoId;
  String sourceText;
  List<double> embedding;
  String model;
  String createdAt;
  String updatedAt;

  VideoEmbeddingRecord({
    required this.videoId,
    required this.sourceText,
    required this.embedding,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VideoEmbeddingRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['embedding'];
    final List<double> decoded;
    if (raw is Uint8List) {
      final bytes = ByteData.sublistView(raw);
      decoded = List.generate(raw.length ~/ 4, (i) => bytes.getFloat32(i * 4, Endian.little));
    } else {
      final text = (raw ?? '').toString();
      decoded = text.isEmpty ? [] : (jsonDecode(text) as List).map((e) => (e as num).toDouble()).toList();
    }
    return VideoEmbeddingRecord(
      videoId: (json['video_id'] ?? '').toString(),
      sourceText: (json['source_text'] ?? '').toString(),
      embedding: decoded,
      model: (json['model'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'source_text': sourceText,
      'embedding': jsonEncode(embedding),
      'model': model,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

mixin DBVideoEmbeddings {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'video_embeddings';

  static Future<void> upsert({
    required String videoId,
    required String sourceText,
    required List<double> embedding,
    String? model,
  }) async {
    final now = DateTime.now().toStringEx();
    final current = await getByVideoId(videoId);
    final record = VideoEmbeddingRecord(
      videoId: videoId,
      sourceText: sourceText,
      embedding: embedding,
      model: model ?? AppPref.getSemanticSearchModel(),
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );

    await _db.insert(
      _tableName,
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<VideoEmbeddingRecord?> getByVideoId(String videoId) async {
    final maps = await _db.query(_tableName, where: 'video_id = ?', whereArgs: [videoId], limit: 1);
    if (maps.isEmpty) return null;
    return VideoEmbeddingRecord.fromJson(maps.first);
  }

  static Future<List<VideoEmbeddingRecord>> getAll() async {
    final maps = await _db.query(_tableName, orderBy: 'updated_at DESC');
    return maps.map((item) => VideoEmbeddingRecord.fromJson(item)).toList();
  }

  static Future<int> getCount() async {
    final maps = await _db.rawQuery('SELECT COUNT(*) as total FROM $_tableName');
    return maps.isEmpty ? 0 : (maps.first['total'] as int? ?? 0);
  }

  static Future<void> deleteAll() async {
    await _db.delete(_tableName);
  }

}
