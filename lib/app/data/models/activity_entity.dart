import 'dart:convert';
import 'dart:core';

const kDownloadStringFields = {'ev', 'status', 'filename', 'url', 'dir', 'mode', 'output_path', 'error', 'referer', 'user_agent', 'play_selector'};
const kDownloadIntegerFields = {'exit_code', 'concurrency', 'retries', 'timeout', 'capture_duration'};
const kDownloadBooleanFields = {'headless', 'allow_popups'};

bool isValidDownloadPayload(Map<String, dynamic> payload) =>
    kDownloadStringFields.every((key) => payload[key] == null || payload[key] is String)
    && kDownloadIntegerFields.every((key) => payload[key] == null || payload[key] is int)
    && kDownloadBooleanFields.every((key) => payload[key] == null || payload[key] is bool);

class Activity {
  String? id;
  String? type;
  String? content;
  String? createdAt;
  String? updatedAt;
  int? times;

  Activity({this.id, this.type, this.content, this.createdAt, this.updatedAt, this.times});

  Activity.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    type = json['type'];
    content = json['content'];
    times = json['times'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['type'] = type;
    data['content'] = content;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }



  @override
  String toString() {
    return jsonEncode(this);
  }
}
