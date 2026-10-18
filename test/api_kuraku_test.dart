import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/api/api_kuraku.dart';

import 'api_test_http_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiTestHttpClient();

  test('metadata lookups are rejected before any request when the code is invalid', () async {
    for (final code in ['', '   ', 'not-a-code', 'ABP', '12345', 'holiday.mp4']) {
      await expectLater(
        ApiKuraku.getMetadata(code: code),
        throwsA(isA<Exception>()),
        reason: 'code "$code" should never reach the network',
      );
    }
  });

  test('provider identifiers match the backend routes', () {
    expect(kProviderR18, 'r18');
    expect(kProviderNJav, 'njav');
  });

  test('search preserves special characters and keeps pagination as separate parameters', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-api-query-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(Get.reset);
    Get.put(AppSettingService()..appPath = directory.path);
    client.requests.clear();
    await HttpOverrides.runZoned(() async {
      for (final query in ['a&b #1 + 50% ? 日本語', 'x&lang=id&page=99', '']) {
        final response = await ApiKuraku.search(s: query, page: 2);
        expect(response.result, isEmpty);
        expect(client.requests.last.path, '/api/njav/search');
        expect(client.requests.last.fragment, isEmpty);
        expect(client.requests.last.queryParameters, {'q': query, 'lang': 'en', 'page': '2'});
      }
      await ApiKuraku.search(s: 'Test', lang: '', page: 0);
      expect(client.requests.last.queryParameters, {'q': 'Test', 'lang': 'en', 'page': '1'});
    }, createHttpClient: (_) => client);
  });

  test('manual metadata requests bypass old responses and reject empty provider payloads', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-api-metadata-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(Get.reset);
    Get.put(AppSettingService()..appPath = directory.path);
    client.requests.clear();
    await HttpOverrides.runZoned(() async {
      client.response = {'video_code': 'ABP-001', 'title': 'First title'};
      expect((await ApiKuraku.getMetadata(code: 'ABP-001')).title, 'First title');
      client.response = {'video_code': 'ABP-001', 'title': 'Updated title'};
      expect((await ApiKuraku.getMetadata(code: 'ABP-001')).title, 'Updated title');
      expect(client.requests, hasLength(2));
      expect(client.requests.last.queryParameters, {'code': 'ABP-001'});
      for (final response in <Map<String, Object?>>[
        {}, {'video_code': 'ABP-001'}, {'title': ' null ', 'genre': [], 'duration': 0},
      ]) {
        client.response = response;
        await expectLater(ApiKuraku.getMetadata(code: 'ABP-001'), throwsA(isA<Exception>()));
      }
      client.response = {'poster': 'digital/video/abp00001/abp00001ps'};
      expect((await ApiKuraku.getMetadata(code: 'ABP-001')).poster, 'digital/video/abp00001/abp00001ps');
    }, createHttpClient: (_) => client);
  });

}
