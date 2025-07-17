import 'package:dio/dio.dart';
import 'package:ex_kit/ex.dart';

import '../../core/app_network.dart';
import '../../core/const.dart';
import '../../utils/helper_misc.dart';

class ApiJavit {
  Future<Map<String, dynamic>> getByCode({required String code, String provider = kProviderR18, String lang = ''}) async {
    if (!HelperMisc.isValidVideoCode(code) || code == '') {
      throw Exception('Invalid video code for $code');
    }

    try {
      Response<dynamic> res;
      if (lang != '') {
        res = await Api.get('/api/$provider/bycode?code=$code&lang=$lang');
      } else {
        res = await Api.get('/api/$provider/bycode?code=$code');
      }
      return res.data;
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
}
