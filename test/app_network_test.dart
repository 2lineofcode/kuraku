import 'dart:typed_data';

import 'package:dio/dio.dart' hide LogInterceptor;
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart' show extraFromNetworkKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/core/app_network.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';

class _Adapter implements HttpClientAdapter {
  int statusCode = 200;
  final responseExtra = <String, dynamic>{};
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    )..extra.addAll(responseExtra);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late Dio dio;

  setUp(() {
    HomePanelAppLog.clear();
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(LogInterceptor());
  });
  tearDown(() {
    dio.close(force: true);
    HomePanelAppLog.clear();
  });

  test('the logging interceptor stamps the request and forwards the response untouched', () async {
    final response = await dio.get('/api/r18/bycode?code=ABP-001');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
    expect(adapter.requests.single.uri.toString(), 'https://example.com/api/r18/bycode?code=ABP-001');
    expect(response.requestOptions.extra['_pdl_timeStamp_'], isA<int>());
    expect(response.requestOptions.extra['_pdl_timeStamp_'], lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
  });

  test('the stamp survives every verb and is refreshed per request', () async {
    final first = await dio.get('/one');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await dio.post('/two', data: {'a': 1});

    expect(adapter.requests.map((request) => request.method), ['GET', 'POST']);
    expect(second.requestOptions.extra['_pdl_timeStamp_'], greaterThanOrEqualTo(first.requestOptions.extra['_pdl_timeStamp_'] as int));
  });

  test('a cached or not modified response is reported without timing noise', () async {
    adapter.statusCode = 304;
    final notModified = await dio.get('/cached', options: Options(validateStatus: (status) => true));
    expect(notModified.statusCode, 304);

    adapter.statusCode = 200;
    adapter.responseExtra[extraFromNetworkKey] = false;
    final fromStore = await dio.get('/stored');
    expect(fromStore.extra[extraFromNetworkKey], isFalse);

    // Logging depends on the configured level, but when it happens the cache
    // marker must be used instead of the elapsed time.
    final entries = HomePanelAppLog.appLogRuntime.where((entry) => entry.content?.contains('/cached') == true || entry.content?.contains('/stored') == true);
    for (final entry in entries) {
      expect(entry.content, contains('Loaded from Cache'));
      expect(entry.content, isNot(contains('ms)')));
    }
  });

  test('a response without a timestamp never breaks the handler', () {
    final interceptor = LogInterceptor();
    final options = RequestOptions(path: '/manual');
    final response = Response<String>(requestOptions: options, statusCode: 200, data: 'body');

    expect(() => interceptor.onResponse(response, ResponseInterceptorHandler()), returnsNormally);
    expect(options.extra.containsKey('_pdl_timeStamp_'), isFalse);

    interceptor.onRequest(options, RequestInterceptorHandler());
    expect(options.extra['_pdl_timeStamp_'], isA<int>());
    expect(() => interceptor.onResponse(response, ResponseInterceptorHandler()), returnsNormally);
  });

  test('Api requires the app settings service before any request is made', () async {
    await expectLater(Api.get('/api/anything'), throwsA(anything), reason: 'no AppSettingService is registered');
  });
}
