import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/app_updater.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _ReleaseAdapter implements HttpClientAdapter {
  Object? data;
  int status = 200;
  DioExceptionType? failure;
  Map<String, List<String>> headers = {};
  RequestOptions? request;
  Completer<void>? pending;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    requests++;
    await pending?.future;
    if (failure != null) throw DioException(requestOptions: options, type: failure!);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {Headers.contentTypeHeader: ['application/json'], ...headers});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _release({String tag = 'v1.0.3', String? asset}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/2lineofcode/kuraku/releases/tag/$tag',
  'body': 'Playback improvements',
  'draft': false,
  'prerelease': false,
  'assets': [
    if (asset != null) {'name': asset, 'browser_download_url': 'https://github.com/2lineofcode/kuraku/releases/download/$tag/$asset'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late _ReleaseAdapter adapter;

  setUp(() {
    AppUpdater.latestRelease = null;
    PackageInfo.setMockInitialValues(appName: 'KuraKu', packageName: 'kuraku', version: '1.0.2', buildNumber: '20261018.94', buildSignature: '');
    adapter = _ReleaseAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() => dio.close(force: true));

  Future<AppRelease?> check({String current = '1.0.2', Abi abi = Abi.macosArm64}) => AppUpdater.check(currentVersion: current, dio: dio, abi: abi);

  test('startup and manual checks share the pending installed-version request', () async {
    adapter.data = _release();
    adapter.pending = Completer<void>();
    final startup = AppUpdater.checkInstalled(dio: dio);
    final manual = AppUpdater.checkInstalled(dio: dio);
    expect(identical(startup, manual), isTrue);
    adapter.pending!.complete();
    expect((await startup)!.version, '1.0.3');
    expect(AppUpdater.latestRelease, same(await startup));
    expect(await manual, same(await startup));
    expect(adapter.requests, 1);
    await AppUpdater.checkInstalled(dio: dio);
    expect(adapter.requests, 2);
  });

  test('installed-version check allows retry after a failed background request', () async {
    adapter.failure = DioExceptionType.connectionError;
    await expectLater(AppUpdater.checkInstalled(dio: dio), throwsA(isA<AppUpdateException>()));
    adapter.failure = null;
    adapter.data = _release(tag: 'v1.0.2');
    expect(await AppUpdater.checkInstalled(dio: dio), isNull);
    expect(adapter.requests, 2);
  });

  test('checks the public stable endpoint and selects the native package', () async {
    for (final target in {
      Abi.macosArm64: 'KuraKu-1.0.3-macos-arm64.dmg',
      Abi.linuxX64: 'KuraKu-1.0.3+20261018.94-linux-x64.deb',
      Abi.windowsX64: 'KuraKu-1.0.3+20261018.94-windows-x64.zip',
    }.entries) {
      adapter.data = _release(asset: target.value);
      final release = (await check(abi: target.key))!;
      expect(release.version, '1.0.3');
      expect(release.notes, 'Playback improvements');
      expect(release.releaseUrl.toString(), 'https://github.com/2lineofcode/kuraku/releases/tag/v1.0.3');
      expect(release.assetName, target.value);
      expect(release.downloadUrl!.pathSegments.last, target.value);
    }
    expect(adapter.request!.uri.toString(), 'https://api.github.com/repos/2lineofcode/kuraku/releases/latest');
    expect(adapter.request!.headers['X-GitHub-Api-Version'], '2022-11-28');
    expect(adapter.request!.followRedirects, isFalse);
  });

  test('compares version components numerically and ignores installed build metadata', () async {
    for (final versions in [
      ('v1.0.10', '1.0.9+20261018.94', true),
      ('v1.1.0', '1.0.99', true),
      ('v2.0.0', '1.99.99', true),
      ('v1.0.3', '1.0.3+20261018.94', false),
      ('v1.0.2', '1.0.3', false),
      ('v1.9.9', '2.0.0', false),
    ]) {
      adapter.data = _release(tag: versions.$1);
      expect(await check(current: versions.$2), versions.$3 ? isNotNull : isNull);
    }
  });

  test('missing or unsupported packages keep the release page available', () async {
    adapter.data = _release(asset: 'KuraKu-1.0.3-macos-arm64.dmg');
    expect((await check(abi: Abi.macosX64))!.downloadUrl, isNull);
    expect((await check(abi: Abi.linuxX64))!.downloadUrl, isNull);
    adapter.data = _release()..['body'] = null;
    expect((await check())!.notes, isEmpty);
  });

  test('draft and prerelease responses do not offer updates', () async {
    for (final flag in ['draft', 'prerelease']) {
      adapter.data = _release()..[flag] = true;
      expect(await check(), isNull);
    }
  });

  test('rejects invalid versions and malformed release data', () async {
    for (final data in [
      [],
      _release(tag: 'v1.0.3-beta.1'),
      _release(tag: 'v01.0.3'),
      _release(tag: '1.0.3'),
      _release()..['assets'] = null,
      _release()..['body'] = 123,
      _release()..['html_url'] = 'https://example.com/download',
      _release()..['html_url'] = 'https://github.com/another/repository/releases/tag/v1.0.3',
    ]) {
      adapter.data = data;
      await expectLater(check(), throwsA(isA<AppUpdateException>().having((e) => e.message, 'message', 'The app release information is invalid.')));
    }
    adapter.data = _release();
    await expectLater(check(current: 'invalid'), throwsA(isA<AppUpdateException>()));
  });

  test('does not offer unsafe or mismatched download URLs', () async {
    const name = 'KuraKu-1.0.3-macos-arm64.dmg';
    for (final url in [
      'http://github.com/2lineofcode/kuraku/releases/download/v1.0.3/$name',
      'https://github.com.evil.test/2lineofcode/kuraku/releases/download/v1.0.3/$name',
      'https://github.com/other/kuraku/releases/download/v1.0.3/$name',
      'https://github.com/2lineofcode/kuraku/releases/download/v1.0.2/$name',
      'https://github.com/2lineofcode/kuraku/releases/download/v1.0.3/$name?redirect=evil',
      'https://user@github.com/2lineofcode/kuraku/releases/download/v1.0.3/$name',
    ]) {
      adapter.data = _release(asset: name)..['assets'][0]['browser_download_url'] = url;
      expect((await check())!.downloadUrl, isNull);
    }
    adapter.data = _release(asset: 'KuraKu-1.0.4-macos-arm64.dmg');
    expect((await check())!.downloadUrl, isNull);
  });

  test('accepts GitHub encoded build metadata in download URLs', () async {
    const name = 'KuraKu-1.0.3+20261018.94-linux-x64.deb';
    adapter.data = _release(asset: name)..['assets'][0]['browser_download_url'] = 'https://github.com/2lineofcode/kuraku/releases/download/v1.0.3/${name.replaceAll('+', '%2B')}';
    expect((await check(abi: Abi.linuxX64))!.assetName, name);
  });

  test('distinguishes no release, rate limit, server failure and connection errors', () async {
    for (final error in {
      404: 'No app releases are available yet.',
      429: 'GitHub rate limit reached. Please try again later.',
      503: 'Could not check for updates. Please try again.',
    }.entries) {
      adapter.status = error.key;
      await expectLater(check(), throwsA(isA<AppUpdateException>().having((e) => e.message, 'message', error.value)));
    }
    adapter.status = 403;
    adapter.headers = {'x-ratelimit-remaining': ['0']};
    await expectLater(check(), throwsA(isA<AppUpdateException>().having((e) => e.message, 'message', contains('rate limit'))));
    for (final type in [DioExceptionType.connectionTimeout, DioExceptionType.receiveTimeout, DioExceptionType.sendTimeout]) {
      adapter.failure = type;
      await expectLater(check(), throwsA(isA<AppUpdateException>().having((e) => e.message, 'message', contains('timed out'))));
    }
    adapter.failure = DioExceptionType.connectionError;
    await expectLater(check(), throwsA(isA<AppUpdateException>().having((e) => e.message, 'message', contains('internet connection'))));
  });
}
