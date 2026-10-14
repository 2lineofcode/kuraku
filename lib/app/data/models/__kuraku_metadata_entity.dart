import 'dart:convert';

/// * 
/// * JSON Source: {"video_id":"eyan00181","video_code_id":"eyan00181","video_code":"EYAN-181","title":"My Older Stepsister Is A Young Mother In Her Breastfeeding Period While In Our Parents' Home. Live Version. Mina Kitano","title_ja":"姉はヤンママ授乳中in実家 実写版 北野未奈","description":null,"fan_art":"https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181pl.jpg","poster":"https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181ps.jpg","trailer":"https://cc3001.dmm.co.jp/litevideo/freepv/e/eya/eyan00181/eyan00181_mhb_w.mp4","actors":[{"cast_id":1068671,"cast_names":"Mina Kitano","cast_image":"https://pics.dmm.co.jp/mono/actjpgs/kitano_mina.jpg"}],"genre":["Married Woman"],"release_date":"2022-05-17","release_date_formated":"May 17, 2022","duration":121,"duration_formated":"2 hrs 1 min","studio":"E-BODY","label":"Wives of Hanasagari","director":"Kitorune Kawaguchi","series":null,"screenshot":["https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181jp-1.jpg"],"view_count":null,"score":null}
/// * Code generated: https://2lineofcode.github.io/json_to_dart2023
/// * 
class KurakuMetadata {
  String? videoId;
  String? videoCodeId;
  String? videoCode;
  String? title;
  String? titleJa;
  dynamic description;
  String? fanArt;
  String? poster;
  String? trailer;
  List<KurakuMetadataActors>? actress;
  List<String>? genre;
  String? releaseDate;
  String? releaseDateFormated;
  num? duration;
  String? durationFormated;
  String? studio;
  String? label;
  String? director;
  dynamic series;
  List<String>? screenshot;
  dynamic viewCount;
  dynamic score;

  KurakuMetadata({this.videoId, this.videoCodeId, this.videoCode, this.title, this.titleJa, this.description, this.fanArt, this.poster, this.trailer, this.actress, this.genre, this.releaseDate, this.releaseDateFormated, this.duration, this.durationFormated, this.studio, this.label, this.director, this.series, this.screenshot, this.viewCount, this.score, });

  KurakuMetadata.fromJson(Map<String, dynamic> json) {
    videoId = json['video_id'] ?? '';
    videoCodeId = json['video_code_id'] ?? '';
    videoCode = json['video_code'] ?? '';
    title = json['title'] ?? '';
    titleJa = json['title_ja'] ?? '';
    description = json['description'] ?? '';
    fanArt = json['fan_art'] ?? '';
    poster = json['poster'] ?? '';
    trailer = json['trailer'] ?? '';
    actress = json['actors'] == null ? null : (json['actors'] as List).map((e) => KurakuMetadataActors.fromJson(e)).toList();
    genre = json['genre'] == null ? null : List<String>.from(json['genre']);
    releaseDate = json['release_date'] ?? '';
    releaseDateFormated = json['release_date_formated'] ?? '';
    duration = json['duration'] ?? 0;
    durationFormated = json['duration_formated'] ?? '';
    studio = json['studio'] ?? '';
    label = json['label'] ?? '';
    director = json['director'] ?? '';
    series = json['series'] ?? '';
    screenshot = json['screenshot'] == null ? null : List<String>.from(json['screenshot']);
    viewCount = json['view_count'] ?? '';
    score = json['score'] ?? '';
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['video_id'] = videoId;
    data['video_code_id'] = videoCodeId;
    data['video_code'] = videoCode;
    data['title'] = title;
    data['title_ja'] = titleJa;
    data['description'] = description;
    data['fan_art'] = fanArt;
    data['poster'] = poster;
    data['trailer'] = trailer;
    if (actress != null) {
      data['actors'] = actress?.map((e) => e.toJson()).toList();
    }
    if (genre != null) {
      data['genre'] = genre;
    }
    data['release_date'] = releaseDate;
    data['release_date_formated'] = releaseDateFormated;
    data['duration'] = duration;
    data['duration_formated'] = durationFormated;
    data['studio'] = studio;
    data['label'] = label;
    data['director'] = director;
    data['series'] = series;
    if (screenshot != null) {
      data['screenshot'] = screenshot;
    }
    data['view_count'] = viewCount;
    data['score'] = score;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class KurakuMetadataActors {
  num? castId;
  String? castNames;
  String? castImage;

  KurakuMetadataActors({this.castId, this.castNames, this.castImage});

  KurakuMetadataActors.fromJson(Map<String, dynamic> json) {
    castId = json['cast_id'] ?? 0;
    castNames = json['cast_names'] ?? '';
    castImage = json['cast_image'] ?? '';
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['cast_id'] = castId;
    data['cast_names'] = castNames;
    data['cast_image'] = castImage;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
