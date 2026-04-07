import 'dart:convert';

import 'package:ex_kit/ex.dart';

import '../../../env.g.dart';
import '../../core/app_network.dart';
import '../models/__javmost_new_release.dart';

mixin ApiJavMost {
  static Map<String, dynamic> _parseMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }

    throw FormatException('Invalid JavMost response type: ${data.runtimeType}');
  }

  static Future<JavMostModel> _fetch(String url) async {
    try {
      final res = await Api.get(url, withCache: false);
      final map = _parseMap(res.data);
      return JavMostModel.fromJson(map);
    } on FormatException catch (e) {
      throw ApiException(e.toString());
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  static Future<JavMostModel> getNewRelease({int page = 1}) async {
    if (page <= 1) page = 1;
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/new/$page/release/');
  }

  static Future<JavMostModel> getTopMonthly({int page = 1}) async {
    if (page <= 1) page = 1;
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/none/$page/topmonth/');
  }

  static Future<JavMostModel> getTopWeekly({int page = 1}) async {
    if (page <= 1) page = 1;
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/none/$page/topweek/');
  }

  static Future<JavMostModel> getTopDaily({int page = 1}) async {
    if (page <= 1) page = 1;
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/none/$page/topdaily/');
  }

  static Future<JavMostModel> getBestRating({int page = 1}) async {
    if (page <= 1) page = 1;
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/none/$page/rating/');
  }

  static Future<JavMostModel> search({String s = '',  int page = 1}) async {
    if (page <= 1) page = 1;
    final q = Uri.encodeComponent(s.trim());
    return _fetch('${Env.proxyUrl}https://www.javmost.ws/showlist2/$q/$page/search/');
  }
}
