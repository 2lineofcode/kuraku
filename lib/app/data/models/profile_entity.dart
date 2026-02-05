import 'dart:convert';

class Profile {
  String? id;
  String? name;
  int? totalWatchDuration;
  String? badgeForWatchDuration;
  String? badgeForCollection;
  String? createdAt;
  String? updatedAt;

  Profile({this.id, this.name, this.totalWatchDuration, this.badgeForWatchDuration, this.badgeForCollection, this.createdAt, this.updatedAt});

  Profile.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    totalWatchDuration = json['total_watch_duration'];
    badgeForWatchDuration = json['badge_for_watch_duration'];
    badgeForCollection = json['badge_for_collection'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['total_watch_duration'] = totalWatchDuration;
    data['badge_for_watch_duration'] = badgeForWatchDuration;
    data['badge_for_collection'] = badgeForCollection;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
