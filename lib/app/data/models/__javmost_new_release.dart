class JavMostModel {
  List<Result>? result;
  bool? success;
  int? total;

  JavMostModel({this.result, this.success, this.total});

  JavMostModel.fromJson(Map<String, dynamic> json) {
    if (json['result'] != null) {
      result = <Result>[];
      json['result'].forEach((v) {
        result!.add(Result.fromJson(v));
      });
    }
    success = json['success'];
    total = json['total'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (result != null) {
      data['result'] = result!.map((v) => v.toJson()).toList();
    }
    data['success'] = success;
    data['total'] = total;
    return data;
  }
}

class Result {
  String? url;
  String? name;
  String? fullName;
  String? cover;
  String? dataPreview;
  String? star;
  String? adsJavmost;
  String? adultAds;
  String? adsJavpost;
  String? ditector;
  String? length;
  String? maker;
  String? genre;
  String? group;
  String? release;
  String? rate;

  Result(
      {this.url,
      this.name,
      this.fullName,
      this.cover,
      this.dataPreview,
      this.star,
      this.adsJavmost,
      this.adultAds,
      this.adsJavpost,
      this.ditector,
      this.length,
      this.maker,
      this.genre,
      this.group,
      this.release,
      this.rate});

  Result.fromJson(Map<String, dynamic> json) {
    url = json['url'];
    name = json['name'];
    fullName = json['full_name'];
    cover = json['cover'];
    dataPreview = json['data_preview'];
    star = json['star'];
    adsJavmost = json['ads_javmost'];
    adultAds = json['adult_ads'];
    adsJavpost = json['ads_javpost'];
    ditector = json['ditector'];
    length = json['length'];
    maker = json['maker'];
    genre = json['genre'];
    group = json['group'];
    release = json['release'];
    rate = json['rate'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['url'] = url;
    data['name'] = name;
    data['full_name'] = fullName;
    data['cover'] = cover;
    data['data_preview'] = dataPreview;
    data['star'] = star;
    data['ads_javmost'] = adsJavmost;
    data['adult_ads'] = adultAds;
    data['ads_javpost'] = adsJavpost;
    data['ditector'] = ditector;
    data['length'] = length;
    data['maker'] = maker;
    data['genre'] = genre;
    data['group'] = group;
    data['release'] = release;
    data['rate'] = rate;
    return data;
  }
}
