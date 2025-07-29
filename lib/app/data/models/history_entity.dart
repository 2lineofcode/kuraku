import 'dart:convert';
import 'dart:core';

class History {
  String? id;
  String? type;
  String? message;
  String? createdAt;
  String? updatedAt;

  History({this.id, this.type, this.message, this.createdAt, this.updatedAt});

  History.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    type = json['type'];
    message = json['message'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['type'] = type;
    data['message'] = message;
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    return data;
  }



  @override
  String toString() {
    return jsonEncode(this);
  }
}
