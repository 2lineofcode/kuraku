import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/videos_entity.dart';
import '_init_db.dart';

class WatchNextQueue {
  final String id;
  final String name;
  final bool isActive;
  final Map<String, dynamic> rules;
  final String createdAt;
  final String updatedAt;

  WatchNextQueue({
    required this.id,
    required this.name,
    required this.isActive,
    required this.rules,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WatchNextQueue.fromMap(Map<String, dynamic> map) {
    return WatchNextQueue(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? 'Watch Next'}',
      isActive: (map['is_active'] ?? 0) == 1,
      rules: map['rules_json'] == null || '${map['rules_json']}'.isEmpty ? <String, dynamic>{} : (jsonDecode(map['rules_json']) as Map<String, dynamic>),
      createdAt: '${map['created_at'] ?? ''}',
      updatedAt: '${map['updated_at'] ?? ''}',
    );
  }
}

class WatchNextItem {
  final String id;
  final String queueId;
  final String? videoId;
  final String videoPath;
  final int position;
  final String status;
  final double score;
  final String? reason;

  WatchNextItem({
    required this.id,
    required this.queueId,
    required this.videoId,
    required this.videoPath,
    required this.position,
    required this.status,
    required this.score,
    required this.reason,
  });

  factory WatchNextItem.fromMap(Map<String, dynamic> map) {
    return WatchNextItem(
      id: '${map['id'] ?? ''}',
      queueId: '${map['queue_id'] ?? ''}',
      videoId: map['video_id']?.toString(),
      videoPath: '${map['video_path'] ?? ''}',
      position: (map['position'] as num?)?.toInt() ?? 0,
      status: '${map['status'] ?? 'pending'}',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      reason: map['reason']?.toString(),
    );
  }
}

mixin DBWatchNext {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _queueTable = 'watch_next_queue';
  static const _itemTable = 'watch_next_item';

  static Future<WatchNextQueue> ensureDefaultQueue() async {
    final all = await getQueues();
    if (all.isNotEmpty) return all.first;

    final now = DateTime.now().toStringEx();
    final queue = WatchNextQueue(
      id: const UuidV4().generate(),
      name: 'Default Queue',
      isActive: true,
      rules: {
        'prefer_unwatched': true,
        'prefer_recent': true,
        'random_mix': 0.25,
        'max_items': 120,
      },
      createdAt: now,
      updatedAt: now,
    );

    await _db.insert(_queueTable, {
      'id': queue.id,
      'name': queue.name,
      'is_active': 1,
      'rules_json': jsonEncode(queue.rules),
      'created_at': now,
      'updated_at': now,
    });
    return queue;
  }

  static Future<List<WatchNextQueue>> getQueues() async {
    final maps = await _db.query(_queueTable, orderBy: 'updated_at DESC');
    return maps.map(WatchNextQueue.fromMap).toList();
  }

  static Future<WatchNextQueue> getActiveQueue() async {
    final maps = await _db.query(_queueTable, where: 'is_active = 1', limit: 1);
    if (maps.isNotEmpty) return WatchNextQueue.fromMap(maps.first);
    return ensureDefaultQueue();
  }

  static Future<void> updateQueueRules(String queueId, Map<String, dynamic> rules) async {
    await _db.update(
      _queueTable,
      {'rules_json': jsonEncode(rules), 'updated_at': DateTime.now().toStringEx()},
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  static Future<void> rebuildItems(String queueId, List<Videos> videos) async {
    await _db.transaction((txn) async {
      await txn.delete(_itemTable, where: 'queue_id = ?', whereArgs: [queueId]);
      for (var i = 0; i < videos.length; i++) {
        final video = videos[i];
        await txn.insert(_itemTable, {
          'id': const UuidV4().generate(),
          'queue_id': queueId,
          'video_id': video.id,
          'video_path': video.videoPath ?? '',
          'position': i + 1,
          'score': 0,
          'status': 'pending',
          'reason': '',
          'created_at': DateTime.now().toStringEx(),
          'updated_at': DateTime.now().toStringEx(),
        });
      }
    });
  }

  static Future<List<WatchNextItem>> getItems(String queueId, {String? status}) async {
    final maps = await _db.query(
      _itemTable,
      where: status == null ? 'queue_id = ?' : 'queue_id = ? AND status = ?',
      whereArgs: status == null ? [queueId] : [queueId, status],
      orderBy: 'position ASC',
    );
    return maps.map(WatchNextItem.fromMap).toList();
  }

  static Future<void> setItemStatus(String itemId, String status, {String? reason}) async {
    await _db.update(
      _itemTable,
      {'status': status, 'reason': reason ?? '', 'updated_at': DateTime.now().toStringEx()},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }
}
