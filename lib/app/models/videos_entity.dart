import 'dart:convert';

/// *
/// * JSON Source: {"video_id":"eyan00181","video_code_id":"eyan00181","video_code":"EYAN-181","title":"My Older Stepsister Is A Young Mother In Her Breastfeeding Period While In Our Parents' Home. Live Version. Mina Kitano","title_ja":"姉はヤンママ授乳中in実家 実写版 北野未奈","description":"null","fan_art":"https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181pl.jpg","poster":"https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181ps.jpg","trailer":"https://cc3001.dmm.co.jp/litevideo/freepv/e/eya/eyan00181/eyan00181_mhb_w.mp4","actress":[{"cast_id":1068671,"cast_names":"Mina Kitano","cast_image":"https://pics.dmm.co.jp/mono/actjpgs/kitano_mina.jpg"}],"genre":["Married Woman"],"release_date":"2022-05-17","release_date_formated":"May 17, 2022","duration":121,"duration_formated":"2 hrs 1 min","studio":"E-BODY","label":"Wives of Hanasagari","director":"Kitorune Kawaguchi","series":"null","screenshot":["https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181jp-1.jpg"],"view_count":121,"score":3.3}
/// * Code generated: https://2lineofcode.github.io/json_to_dart2023
/// *
class Videos {
  // custom
  String? rootPath;
  String? videoPath;
  String? posterPath;
  String? coverPath;
  num? viewCount;

  // required
  String? id;
  String? videoCode;
  String? title;
  String? titleJa;
  String? description;
  String? fanArt;
  String? poster;
  String? trailer;
  List<VideoActress>? actress;
  List<VideoCategory>? category;
  String? releaseDate;
  String? releaseDateFormated;
  num? duration;
  String? durationFormated;
  String? studio;
  String? label;
  String? director;
  String? series;
  List<String>? screenshot;
  String? site;

  Videos({
    this.rootPath,
    this.videoPath,
    this.posterPath,
    this.coverPath,
    this.viewCount,
    this.id,
    this.videoCode,
    this.title,
    this.titleJa,
    this.description,
    this.fanArt,
    this.poster,
    this.trailer,
    this.actress,
    this.category,
    this.releaseDate,
    this.releaseDateFormated,
    this.duration,
    this.durationFormated,
    this.studio,
    this.label,
    this.director,
    this.series,
    this.screenshot,
    this.site,
  });

  Videos.fromJson(Map<String, dynamic> json) {
    rootPath = json['root_path'] ?? '';
    videoPath = json['video_path'] ?? '';
    posterPath = json['poster_path'] ?? '';
    coverPath = json['cover_path'] ?? '';

    id = json['id'] ?? '';
    videoCode = json['video_code'] ?? '';
    title = json['title'] ?? '';
    titleJa = json['title_ja'] ?? '';
    description = json['description'] ?? '';
    fanArt = json['fan_art'] ?? '';
    poster = json['poster'] ?? '';
    trailer = json['trailer'] ?? '';
    actress = json['actress'] == null || (json['actress'] as String).isEmpty ? null : (jsonDecode(json['actress']) as List).map((e) => VideoActress.fromJson(e)).toList();
    category = json['category'] == null || (json['category'] as String).isEmpty ? null : (jsonDecode(json['category']) as List).map((e) => VideoCategory.fromJson(e)).toList();
    
    releaseDate = json['release_date'] ?? '';
    releaseDateFormated = json['release_date_formated'] ?? '';
    duration = json['duration'] ?? 0;
    durationFormated = json['duration_formated'] ?? '';
    studio = json['studio'] ?? '';
    label = json['label'] ?? '';
    director = json['director'] ?? '';
    series = json['series'] ?? '';
    screenshot = json['screenshot'] == null || (json['screenshot'] as String).isEmpty ? null : List<String>.from(jsonDecode(json['screenshot']));
    viewCount = json['view_count'] ?? 0;
    site = json['site'] ?? 0.0;
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['root_path'] = rootPath;
    data['video_path'] = videoPath;
    data['poster_path'] = posterPath;
    data['cover_path'] = coverPath;

    data['id'] = id;
    data['video_code'] = videoCode;
    data['title'] = title;
    data['title_ja'] = titleJa;
    data['description'] = description;
    data['fan_art'] = fanArt;
    data['poster'] = poster;
    data['trailer'] = trailer;

    if (actress != null) {
      data['actress'] = jsonEncode(actress?.map((e) => e.toJson()).toList());
    } else {
      data['actress'] = null;
    }

    if (category != null) {
      data['category'] = jsonEncode(category?.map((e) => e.toJson()).toList());
    } else {
      data['category'] = null;
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
      data['screenshot'] = jsonEncode(screenshot);
    } else {
      data['screenshot'] = null;
    }

    data['view_count'] = viewCount;
    data['site'] = site;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class VideoCategory {
  num? id;
  String? category;

  VideoCategory({this.id, this.category});

  VideoCategory.fromJson(Map<String, dynamic> json) {
    id = json['id'] ?? 0;
    category = json['category'] ?? '';
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['category'] = category;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class VideoActress {
  num? id;
  String? nameRomaji;
  String? imageUrl;

  VideoActress({this.id, this.nameRomaji, this.imageUrl});

  VideoActress.fromJson(Map<String, dynamic> json) {
    id = json['id'] ?? 0;
    nameRomaji = json['name_romaji'] ?? '';
    imageUrl = json['image_url'] ?? '';
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['name_romaji'] = nameRomaji;
    data['image_url'] = imageUrl;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
