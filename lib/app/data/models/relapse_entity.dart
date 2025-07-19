import 'package:ex_kit/ex.dart';

class Relapse {
  String? id;
  String? date;
  String? createdAt;
  String? updatedAt;

  Relapse({this.id, this.date, this.createdAt, this.updatedAt});

  Relapse.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    date = json['date'];
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['date'] = date;
    data['created_at'] = createdAt ?? DateTime.now().toStringEx();
    data['updated_at'] = updatedAt ?? DateTime.now().toStringEx();
    return data;
  }
}
