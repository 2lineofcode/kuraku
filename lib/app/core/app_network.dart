import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:ex_kit/ex.dart';
import 'package:get/get.dart' hide Response;

import '../../env.g.dart';
import 'app_setting.dart';

mixin Api {
  static CacheOptions _defaultCacheOption(String appDirPath) => CacheOptions(
        store: HiveCacheStore(appDirPath),
        policy: CachePolicy.forceCache,
        priority: CachePriority.high,
        maxStale: 360.days,
        hitCacheOnErrorExcept: [401, 404],
        keyBuilder: (request) => request.uri.toString(),
        allowPostMethod: false,
      );

  static final _dio = Dio(
    BaseOptions(baseUrl: Env.apiUrl, connectTimeout: 30.seconds, receiveTimeout: 30.seconds),
  )..interceptors.addAll([
      DioCacheInterceptor(options: _defaultCacheOption(Get.find<AppSettingService>().appDir.path)),
      LogInterceptor(),
    ]);

  static Future<Response> get(String url, {Map<String, dynamic>? queryParameters, bool noCache = false}) async {
    final appSettingService = Get.find<AppSettingService>();
    final cacheOptions = _defaultCacheOption(appSettingService.appDir.path).copyWith(
      policy: noCache ? CachePolicy.noCache : CachePolicy.forceCache,
    );

    return await _dio.get(
      url,
      queryParameters: queryParameters,
      options: cacheOptions.toOptions(),
      cancelToken: CancelToken(),
      onReceiveProgress: (count, total) {},
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

  Future<Response> head(String url, {Map<String, dynamic>? data}) async {
    return await _dio.head(url, data: data);
  }

  static Future<Response> download(
    String url,
    String savePath, {
    void Function(int, int)? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
  }) async {
    return await _dio.download(url, savePath, onReceiveProgress: onReceiveProgress, queryParameters: queryParameters);
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
      print('⚡ [$method] $uri >> Loaded from Cache');
    } else {
      final diffInMs = diff;
      final diffInSec = (diff / 1000).toStringAsFixed(2);
      print('🟢 [$method] $uri | $status | ${diffInSec}s ($diffInMs ms)');
    }

    super.onResponse(response, handler);
  }
}
