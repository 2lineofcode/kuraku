import 'package:ex_kit/ex.dart';

import '../../core/app_network.dart';
import '../../core/app_translations.dart';
import '../../utils/helper_misc.dart';
import '../models/__kuraku_metadata_entity.dart';
import '../models/__kuraku_search_entity.dart';
import 'api_javtrailers.dart';

const kProviderR18 = 'r18';
const kProviderNJav = 'njav';

mixin ApiKuraku {
  static Future<String> resolveTrailerUrl(String url, {String code = ''}) async {
    url = url.trim();
    final host = Uri.tryParse(url)?.host ?? '';
    if (code.trim().isNotEmpty && (url.isEmpty || host.endsWith('.dmm.co.jp') || host.endsWith('.dmm.com') || host == 'media.javtrailers.com')) {
      return ApiJavTrailers.getTrailer(code);
    }
    return url;
  }

  static Future<KurakuMetadata> getMetadata({required String code}) async {
    code = code.trim().toUpperCase();
    if (code.isValidVideoCode() == false) {
      throw Exception('Invalid video code for @{code}'.trNamed({'code': code}));
    }
    code = code.getVideoCode();

    try {
      final res = await Api.get('/api/$kProviderR18/bycode?code=$code');
      return KurakuMetadata.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  static Future<KurakuSearch> search({required String s, String provider = kProviderNJav, String lang = 'en', int page = 1}) async {
    if (page <= 1) page = 1;

    if (lang == '') lang = 'en';
    try {
      final res = await Api.get('/api/$provider/search?q=$s&lang=$lang&page=$page', withCache: false);
      return KurakuSearch.fromJson(res.data);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
}
