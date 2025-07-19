import 'dart:convert';
import 'dart:core';

import 'videos_entity.dart';

class History {
  String? id;
  List<Videos>? videos;
  String? createdAt;
  String? updatedAt;

  History({this.id, this.videos, this.createdAt, this.updatedAt});

  History.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    videos = json['videos'] != null ? List<Videos>.from(json['videos'].map((v) => Videos.fromJson(v))) : null;
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['videos'] = jsonEncode(videos);
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }



  @override
  String toString() {
    return jsonEncode(this);
  }
}
