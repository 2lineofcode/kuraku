import 'dart:convert';

/// *
/// * JSON Source: {"id":"","total_video":4,"root_folder":"","sub_folder":["a"],"videos":["a"]}
/// * Code generated: https://2lineofcode.github.io/json_to_dart2023
/// *
class Library {
  String? id;
  num? totalVideo;
  String? alias;
  String? rootFolder;
  List<String>? subFolder;
  List<String>? videos;

  Library({
    this.id,
    this.totalVideo,
    this.alias,
    this.rootFolder,
    this.subFolder,
    this.videos,
  });

  Library.fromJson(Map<String, dynamic> json) {
    id = json['id'] ?? '';
    totalVideo = json['total_video'] ?? 0;
    alias = json['alias'] ?? '';
    rootFolder = json['root_folder'] ?? '';
    subFolder = json['sub_folder'] == null || (json['sub_folder'] as String).isEmpty ? null : List<String>.from(jsonDecode(json['sub_folder']));
    videos = json['videos'] == null || (json['videos'] as String).isEmpty ? null : List<String>.from(jsonDecode(json['videos']));
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['total_video'] = totalVideo;
    data['alias'] = alias;
    data['root_folder'] = rootFolder;
    if (subFolder != null) {
      data['sub_folder'] = jsonEncode(subFolder);
    } else {
      data['sub_folder'] = null;
    }
    if (videos != null) {
      data['videos'] = jsonEncode(videos);
    } else {
      data['videos'] = null;
    }
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
