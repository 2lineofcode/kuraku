import 'dart:convert';

import 'package:ex_kit/ex.dart';

import 'videos_entity.dart';

class PlaylistHeader {
  String? id;
  String? name;
  String? createdAt;
  String? updatedAt;

  PlaylistHeader({this.id, this.name, this.createdAt, this.updatedAt});

  PlaylistHeader.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class PlaylistItem {
  String? id;
  String? headerId;
  Videos? video;
  String? createdAt;
  String? updatedAt;

  PlaylistItem({this.id, this.headerId, this.video, this.createdAt, this.updatedAt});

  PlaylistItem.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    headerId = json['header_id'];
    video = json['video'] != null ? Videos.fromJson(json['video']) : null;
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['header_id'] = headerId;
    data['video'] = video?.toJson();
    data['created_at'] = createdAt ?? DateTime.now().toStringEx();
    data['updated_at'] = updatedAt ?? DateTime.now().toStringEx();
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
