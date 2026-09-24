import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/chat_entity.dart';
import '_init_db.dart';

mixin DBChat {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> recoverInterrupted(Database db) async {
    await db.update('chat_message', {
      'status': 'failed', 'error_message': 'Response interrupted when the app closed.',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: "role = 'assistant' AND status IN ('pending', 'streaming')");
  }

  static Future<List<ChatConversation>> getConversations() async {
    final rows = await _db.query('chat_conversation', orderBy: 'last_activity_at DESC, id');
    return rows.map(ChatConversation.fromJson).toList();
  }

  static Future<List<ChatMessage>> getMessages(String id) async {
    final rows = await _db.query('chat_message', where: 'conversation_id = ?', whereArgs: [id], orderBy: 'position ASC');
    return rows.map(ChatMessage.fromJson).toList();
  }

  static Future<void> _save(DatabaseExecutor db, Map<String, Object?> values, bool persisted) async {
    if (persisted) {
      final count = await db.update('chat_conversation', values, where: 'id = ?', whereArgs: [values['id']]);
      if (count != 1) throw StateError('Chat no longer exists');
    } else {
      await db.insert('chat_conversation', values);
    }
  }

  static Future<void> saveConversation(ChatConversation chat) async {
    final values = chat.toJson()..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _save(_db, values, chat.persisted);
    chat.persisted = true;
    chat.updatedAt = values['updated_at'] as String;
  }

  static Future<ChatMessage> send(ChatConversation chat, String text) async {
    if (text.trim().isEmpty) throw ArgumentError('Message cannot be empty');
    final now = DateTime.now().toUtc().toIso8601String();
    final title = chat.messages.isEmpty && chat.title == 'New chat'
        ? text.trim().replaceAll(RegExp(r'\s+'), ' ').characters.take(60).toString() : chat.title;
    final message = await _db.transaction((txn) async {
      await _save(txn, chat.toJson()..addAll({'title': title, 'draft': '', 'updated_at': now, 'last_activity_at': now}), chat.persisted);
      final rows = await txn.rawQuery('SELECT COALESCE(MAX(position), 0) + 1 AS position FROM chat_message WHERE conversation_id = ?', [chat.id]);
      final values = <String, Object?>{
        'id': UuidV4().generate(), 'conversation_id': chat.id, 'position': rows.first['position'],
        'role': 'user', 'content': text.trim(), 'status': 'completed', 'created_at': now, 'updated_at': now,
      };
      await txn.insert('chat_message', values);
      return ChatMessage.fromJson(values);
    });
    chat..persisted = true..title = title..draft = ''..updatedAt = now..lastActivityAt = now;
    return message;
  }

  static Future<ChatMessage> addAssistant(ChatConversation chat, String model) async {
    return _db.transaction((txn) async {
      final rows = await txn.rawQuery('SELECT COALESCE(MAX(position), 0) + 1 AS position FROM chat_message WHERE conversation_id = ?', [chat.id]);
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': UuidV4().generate(), 'conversation_id': chat.id, 'position': rows.first['position'],
        'role': 'assistant', 'content': '', 'status': 'pending', 'provider': 'agnes', 'model': model,
        'created_at': now, 'updated_at': now,
      };
      await txn.insert('chat_message', values);
      return ChatMessage.fromJson(values);
    });
  }

  static Future<void> resetAssistant(ChatMessage message) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await _db.update('chat_message', {
      'content': '', 'status': 'pending', 'error_message': null, 'activity': '{}', 'updated_at': now,
    }, where: 'id = ?', whereArgs: [message.id]);
    if (count != 1) throw StateError('Chat message no longer exists');
    message..content = ''..status = 'pending'..errorMessage = null..elapsedMs = 0..updatedAt = now;
    message.activity.clear();
    message.titleSearch = null;
  }

  static Future<void> saveAssistant(ChatMessage message) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await _db.update('chat_message', {
      'content': message.content, 'status': message.status, 'error_message': message.errorMessage, 'updated_at': now,
      'activity': jsonEncode({'steps': message.activity, 'elapsed_ms': message.elapsedMs, 'title_search': message.titleSearch}),
    }, where: 'id = ?', whereArgs: [message.id]);
    if (count != 1) throw StateError('Chat message no longer exists');
    message.updatedAt = now;
  }

  static Future<void> rename(ChatConversation chat, String title) async {
    final value = title.trim();
    if (value.isEmpty) throw ArgumentError('Title cannot be empty');
    final now = DateTime.now().toUtc().toIso8601String();
    await _save(_db, chat.toJson()..addAll({'title': value, 'updated_at': now}), chat.persisted);
    chat..persisted = true..title = value..updatedAt = now;
  }

  static Future<String?> getTranslation(String title) async {
    final rows = await _db.query('chat_translation', where: 'source_text = ? AND target_language = ?', whereArgs: [title, 'id'], limit: 1);
    return rows.isEmpty ? null : rows.first['translated_text'] as String;
  }

  static Future<void> saveTranslation(String title, String translated) async {
    await _db.insert('chat_translation', {
      'source_text': title, 'target_language': 'id', 'translated_text': translated,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> clear(ChatConversation chat) async {
    if (chat.persisted) {
      await _db.transaction((txn) async {
        await txn.delete('chat_message', where: 'conversation_id = ?', whereArgs: [chat.id]);
        await _save(txn, chat.toJson()..['draft'] = '', true);
      });
    }
    chat.messages.clear();
    chat.draft = '';
  }

  static Future<void> delete(String id) async {
    await _db.delete('chat_conversation', where: 'id = ?', whereArgs: [id]);
  }
}
