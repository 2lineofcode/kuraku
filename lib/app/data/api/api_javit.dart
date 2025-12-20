import 'package:ex_kit/ex.dart';

import '../../core/app_network.dart';
import '../../utils/helper_misc.dart';
import '../models/__javit_metadata_entity.dart';
import '../models/__javit_search_entity.dart';

const kProviderR18 = 'r18';
const kProviderNJav = 'njav';

mixin ApiJavit {
  static Future<JavitMetadata> getMetadata({required String code}) async {
    if (code.isValidVideoCode() == false) {
      throw Exception('Invalid video code for $code');
    }

    try {
      final res = await Api.get('/api/$kProviderR18/bycode?code=$code');
      return JavitMetadata.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  static Future<JavitSearch> search({required String s, String provider = kProviderNJav, String lang = 'en', int page = 1}) async {
    if (page <= 1) page = 1;

    if (lang == '') lang = 'en';
    try {
      final res = await Api.get('/api/$provider/search?q=$s&lang=$lang&page=$page', withCache: false);
      return JavitSearch.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  // static Future<Map<String, dynamic>> ranking({String provider = kProviderNJav}) async {
  //   try {
  //     final res = await Api.get('/api/$provider/star_rank', withCache: false);
  //     return res.data;
  //   } catch (e) {
  //     throw ApiException(e.toString());
  //   }
  // }
}
