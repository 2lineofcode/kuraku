import 'dart:convert';

import 'package:uuid/v4.dart';

class ChatConversation {
  ChatConversation() : id = UuidV4().generate(), createdAt = DateTime.now().toUtc().toIso8601String() {
    updatedAt = createdAt;
    lastActivityAt = createdAt;
  }

  final String id;
  final String createdAt;
  String title = 'New chat';
  String draft = '';
  bool isPinned = false;
  late String updatedAt;
  late String lastActivityAt;
  bool persisted = false;
  final messages = <ChatMessage>[];

  ChatConversation.fromJson(Map<String, Object?> json)
      : id = json['id'] as String, createdAt = json['created_at'] as String {
    title = json['title'] as String;
    draft = json['draft'] as String;
    isPinned = json['is_pinned'] == 1;
    updatedAt = json['updated_at'] as String;
    lastActivityAt = json['last_activity_at'] as String;
    persisted = true;
  }

  Map<String, Object?> toJson() => {
    'id': id, 'title': title, 'draft': draft, 'is_pinned': isPinned ? 1 : 0,
    'created_at': createdAt, 'updated_at': updatedAt, 'last_activity_at': lastActivityAt,
  };
}

class ChatMessage {
  ChatMessage.fromJson(Map<String, Object?> json)
      : id = json['id'] as String,
        conversationId = json['conversation_id'] as String,
        position = json['position'] as int,
        role = json['role'] as String,
        content = json['content'] as String,
        status = json['status'] as String,
        provider = json['provider'] as String?,
        model = json['model'] as String?,
        errorMessage = json['error_message'] as String?,
        createdAt = json['created_at'] as String,
        updatedAt = json['updated_at'] as String {
    try {
      final detail = jsonDecode(json['activity'] as String? ?? '{}');
      if (detail is Map) {
        if (detail['steps'] is List) activity.addAll((detail['steps'] as List).whereType<String>().take(20));
        if (detail['title_search'] is Map) titleSearch = Map<String, dynamic>.from(detail['title_search'] as Map);
        elapsedMs = detail['elapsed_ms'] is int ? detail['elapsed_ms'] as int : 0;
      }
    } on FormatException { /* Ignore invalid optional activity metadata. */ }
  }

  final String id, conversationId, role, createdAt;
  String content, status, updatedAt;
  final int position;
  String? provider, model;
  String? errorMessage;
  final activity = <String>[];
  int elapsedMs = 0;
  Map<String, dynamic>? titleSearch;
}
