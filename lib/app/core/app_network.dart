import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:ex_kit/ex.dart';
import 'package:get/get.dart' hide Response;

import '../../env.g.dart';
import 'app_setting.dart';

mixin Api {
  static final _option = CacheOptions(
    store: HiveCacheStore(Get.find<AppSettingService>().appDir.path),
    policy: CachePolicy.forceCache,
    priority: CachePriority.high,
    maxStale: 360.days,
    hitCacheOnErrorExcept: [401, 404],
    keyBuilder: (request) => request.uri.toString(),
    allowPostMethod: false,
  );

  static final _dio = Dio(
    BaseOptions(baseUrl: Env.apiUrl, connectTimeout: 15.seconds, receiveTimeout: 15.seconds),
  )..interceptors.addAll([
      DioCacheInterceptor(options: _option),
      LogInterceptor(),
    ]);

  static Future<Response> get(String url, {Map<String, dynamic>? queryParameters, noCache = false}) async {
    // _dio.interceptors.add(RetryInterceptor(dio: _dio, logPrint: (object) => log(object.toString())));
    return await _dio.get(
      url,
      queryParameters: queryParameters,
      options: _option.copyWith(policy: noCache ? CachePolicy.noCache : CachePolicy.forceCache).toOptions(),
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

    if (diff < 900) {
      // final getCode = response.requestOptions.uri.toString().split('?code=').last;
      // print('$getCode >> Load from Cache');
    } else {
      print('${response.requestOptions.uri} | ${response.statusCode} | $diff ms', name: response.requestOptions.method);
    }
    super.onResponse(response, handler);
  }
}
