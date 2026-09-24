import 'dart:convert';


class Playlist {
  String? id;
  String? name;
  String? cover;
  String? createdAt;
  String? updatedAt;
  int total = 0;

  Playlist({this.id, this.name, this.cover, this.createdAt, this.updatedAt, this.total = 0});

  Playlist.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    cover = json['cover'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
    total = json['total'] ?? 0;
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['cover'] = cover;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
