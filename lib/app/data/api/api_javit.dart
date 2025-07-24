import 'package:ex_kit/ex.dart';

import '../../core/app_network.dart';
import '../../utils/helper_misc.dart';
import '../models/__javit_metadata_entity.dart';
import '../models/__javit_search_entity.dart';

const kProviderR18 = 'r18';
const kProviderNJav = 'njav';
const kProviderMissAV = 'missav';

class ApiJavit {
  Future<JavitMetadata> getMetadata({required String code}) async {
    if (!HelperMisc.isValidVideoCode(code) || code == '') {
      throw Exception('Invalid video code for $code');
    }

    try {
      final res = await Api.get('/api/$kProviderR18/bycode?code=$code');
      return JavitMetadata.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<JavitSearch> search({required String s, String provider = kProviderNJav, String lang = 'en', int page = 1}) async {
    if (lang == '') lang = 'en';
    try {
      final res = await Api.get('/api/$provider/search?q=$s&lang=$lang&page=$page', noCache: true);
      return JavitSearch.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<Map<String, dynamic>> ranking({String provider = kProviderNJav}) async {
    try {
      final res = await Api.get('/api/$provider/star_rank', noCache: true);
      return res.data;
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
}
