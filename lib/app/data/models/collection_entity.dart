import 'dart:convert';


class Collection {
  String? id;
  String? type;
  String? name;
  String? cover;
  String? videoId;
  String? createdAt;
  String? updatedAt;
  int? total;

  Collection({this.id, this.type, this.name, this.cover, this.videoId, this.createdAt, this.updatedAt, this.total});

  Collection.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    type = json['type'];
    name = json['name'];
    cover = json['cover'];
    videoId = json['video_id'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
    total = json['total'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['type'] = type;
    data['name'] = name;
    data['cover'] = cover;
    data['video_id'] = videoId;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
