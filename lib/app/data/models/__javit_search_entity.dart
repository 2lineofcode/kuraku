import 'dart:convert';

/// *
/// * JSON Source: {"code":200,"server_time":1753357535595,"page":1,"total":12,"has_next_page":true,"result":[{"video_id":"hawa-360","video_code":"HAWA-360","title":"Sakura-san (28 years old) who started a men&#039;s beauty salon at home because he was struggling financially. Creampie sex with a single mother from...","fan_art":"https://fourhoi.com/hawa-360/cover-t.jpg","poster":"https://fourhoi.com/hawa-360/cover-t.jpg","trailer":"https://fourhoi.com/hawa-360/preview.mp4"}]}
/// * Code generated: https://2lineofcode.github.io/json_to_dart2023
/// *
class JavitSearch {
  num? code;
  num? serverTime;
  int? page;
  num? total;
  bool? hasNextPage;
  List<JavitSearchResult>? result;

  JavitSearch({this.code, this.serverTime, this.page, this.total, this.hasNextPage, this.result});

  JavitSearch.fromJson(Map<String, dynamic> json) {
    code = json['code'] ?? 0;
    serverTime = json['server_time'] ?? 0;
    page = json['page'] ?? 0;
    total = json['total'] ?? 0;
    hasNextPage = json['has_next_page'] ?? false;
    result = json['result'] == null ? null : (json['result'] as List).map((e) => JavitSearchResult.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['code'] = code;
    data['server_time'] = serverTime;
    data['page'] = page;
    data['total'] = total;
    data['has_next_page'] = hasNextPage;
    if (result != null) {
      data['result'] = result?.map((e) => e.toJson()).toList();
    }
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class JavitSearchResult {
  String? videoId;
  String? videoCode;
  String? title;
  String? fanArt;
  String? poster;
  String? trailer;
  num? duration;
  String? durationFormated;

  JavitSearchResult({
    this.videoId,
    this.videoCode,
    this.title,
    this.fanArt,
    this.poster,
    this.trailer,
    this.duration,
    this.durationFormated,
  });

  JavitSearchResult.fromJson(Map<String, dynamic> json) {
    videoId = json['video_id'] ?? '';
    videoCode = json['video_code'] ?? '';
    title = json['title'] ?? '';
    fanArt = json['fan_art'] ?? '';
    poster = json['poster'] ?? '';
    trailer = json['trailer'] ?? '';
    duration = json['duration'] ?? 0;
    durationFormated = json['duration_formated'] ?? '';
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['video_id'] = videoId;
    data['video_code'] = videoCode;
    data['title'] = title;
    data['fan_art'] = fanArt;
    data['poster'] = poster;
    data['trailer'] = trailer;
    data['duration'] = duration;
    data['duration_formated'] = durationFormated;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
