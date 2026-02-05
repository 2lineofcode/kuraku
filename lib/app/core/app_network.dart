import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:ex_kit/ex.dart';
import 'package:get/get.dart' hide Response;
import 'package:http_cache_sembast_store/http_cache_sembast_store.dart';

import '../../env.g.dart';
import 'app_logging.dart';
import 'app_setting.dart';

mixin Api {
  // https://pub.dev/packages/dio_cache_interceptor
  // cache strategy, hit once keep 5 year 
  static CacheOptions _cacheOption(String appPath) => CacheOptions(
        store: SembastCacheStore(storePath: appPath, cacheStore: 'javit.dio'),
        policy: CachePolicy.forceCache,
        priority: CachePriority.high,
        maxStale: 1825.days, // 5 years
        keyBuilder: ({body, headers, required url}) => url.toString(),
        allowPostMethod: false,
      );

  // ** client
  static final _dio = Dio(
    BaseOptions(baseUrl: Env.apiUrl, connectTimeout: 30.seconds, receiveTimeout: 30.seconds),
  )..interceptors.addAll([
      DioCacheInterceptor(options: _cacheOption(Get.find<AppSettingService>().appPath)),
      LogInterceptor(),
    ]);

  // ────────────────────────────────────────────────────────────────
  // ⵌ GET
  // only method [get] support cache
  // @params [url] required*
  // @params [queryParameters]
  // @params [withCache] default true
  // ────────────────────────────────────────────────────────────────
  static Future<Response> get(String url, {Map<String, dynamic>? queryParameters, bool withCache = true}) async {
    final appSettingService = Get.find<AppSettingService>();
    final cacheOptions = _cacheOption(appSettingService.appPath).copyWith(
      // withCache=true => allow cached response, otherwise bypass cache
      policy: withCache ? CachePolicy.forceCache : CachePolicy.noCache,
    );

    return await _dio.get(
      url,
      queryParameters: queryParameters,
      options: cacheOptions.toOptions(),
      cancelToken: CancelToken(),
    );
  }

  static Future<Response> post(String url, {Map<String, dynamic>? data, Map<String, dynamic>? queryParameters}) async {
    return await _dio.post(url, data: data, queryParameters: queryParameters);
  }

  static Future<Response> put(String url, {Map<String, dynamic>? data}) async {
    return await _dio.put(url, data: data);
  }

  static Future<Response> delete(String url, {Map<String, dynamic>? data}) async {
    return await _dio.delete(url, data: data);
  }

  static Future<Response> patch(String url, {Map<String, dynamic>? data}) async {
    return await _dio.patch(url, data: data);
  }

  static Future<Response> head(String url, {Map<String, dynamic>? data}) async {
    return await _dio.head(url, data: data);
  }
}

class LogInterceptor extends Interceptor {
  final _timeStampKey = '_pdl_timeStamp_';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_timeStampKey] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final triggerTime = response.requestOptions.extra[_timeStampKey];
    int diff = 0;

    if (triggerTime is int) {
      diff = DateTime.now().millisecondsSinceEpoch - triggerTime;
    }

    final uri = response.requestOptions.uri;
    final method = response.requestOptions.method;
    final status = response.statusCode;

    final isCache = response.extra['cacheHit'] == true || status == 304;

    if (isCache) {
      AppLog.logD('⚡ [$method] $uri | $status >> Loaded from Cache');
    } else {
      final diffInMs = diff;
      final diffInSec = (diff / 1000).toStringAsFixed(2);
      AppLog.logD('🟢 [$method] $uri | $status | ${diffInSec}s ($diffInMs ms)');
    }

    super.onResponse(response, handler);
  }
}
