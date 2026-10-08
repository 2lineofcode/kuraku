// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/api/api_javit.dart';
import 'package:javit/app/data/api/api_javtrailers.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/__javit_search_entity.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/utils/helper_opener.dart';
import 'package:javit/env.g.dart';
import 'package:toastification/toastification.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _UnavailableTrailerPlatform extends VideoPlayerPlatform {
  final sources = <String>[];
  final disposed = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource.uri!);
    return sources.length;
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(int playerId, bool preventsDisplaySleepDuringVideoPlayback) async {
    throw StateError('Source unavailable');
  }

  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);
}

class _AvailableTrailerPlatform extends _UnavailableTrailerPlatform {
  Size size = const Size(1920, 1080);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    yield VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(minutes: 2), size: size);
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(int playerId, bool preventsDisplaySleepDuringVideoPlayback) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}

void main() {
  test('matches the exact DVD code and uses the published mirror URL', () {
    const source = '<script type="application/json" id="__NUXT_DATA__">'
        '[{"dvdId":1,"contentId":2,"trailer":3,"trailerG":4},"FNS-140","1fns00140",'
        '"https://cc3001.dmm.co.jp/hlsvideo/freepv/1/1fn/1fns140/playlist.m3u8",'
        '"https://media.javtrailers.com/hlsvideo/freepv/1/1fn/1fns00140/playlist.m3u8"]</script>';
    final video = ApiJavTrailers.parseVideo(source, ' fns-140 ');
    expect(video?['content_id'], '1fns00140');
    expect(video?['trailer'], 'https://media.javtrailers.com/hlsvideo/freepv/1/1fn/1fns00140/playlist.m3u8');
    expect(ApiJavTrailers.parseVideo(source, 'FNS-141'), isNull);
    expect(HelperOpener.trailerUrls(video!['trailer']!), [video['trailer']]);
  });

  test('handles search records, invalid references and verification pages', () {
    const source = '<script id="__NUXT_DATA__">'
        '[{"dvdId":2,"contentId":99},{"dvdId":2,"contentId":3},'
        '"FNS-140","1fns00140"]</script>';
    expect(ApiJavTrailers.parseVideo(source, 'FNS-140'), {'content_id': '1fns00140', 'trailer': ''});
    expect(() => ApiJavTrailers.parseVideo('<html>Verification required</html>', 'FNS-140'), throwsFormatException);
    expect(() => ApiJavTrailers.parseVideo('<script id="__NUXT_DATA__">{}</script>', 'FNS-140'), throwsFormatException);
    expect(HelperOpener.trailerUrls('https://www.dmm.co.jp/litevideo/-/part/=/cid=1fns140/'), isEmpty);
  });

  test('keeps non-DMM previews without querying another provider', () async {
    const url = 'https://fourhoi.com/hawa-360/preview.mp4';
    expect(await ApiJavit.resolveTrailerUrl(url, code: 'HAWA-360'), url);
  });

  test('uses search, library and map trailers without requiring R18', () async {
    const url = 'https://fourhoi.com/hawa-360/preview.mp4';
    final items = [
      JavitSearchResult(videoCode: 'hawa-360', title: 'Search', trailer: ' $url '),
      Videos(videoPath: '/movies/HAWA-360.mp4', title: 'Library', trailer: url),
      {'video_code': 'hawa-360', 'title': 'Explore', 'trailer': url, 'actress': []},
    ];
    for (final item in items) {
      final video = await HelperOpener.resolveTrailerVideo(item);
      expect(video.videoCode, 'HAWA-360');
      expect(video.trailer, url);
      expect(video.title, isNotEmpty);
    }
  });

  test('keeps the code for metadata lookup when R18 is unavailable', () async {
    Get.put(DBService());
    addTearDown(Get.reset);
    final video = await HelperOpener.resolveTrailerVideo({'video_code': ' eyan-181 '});
    expect(video.videoCode, 'EYAN-181');
    expect(video.trailer, isEmpty);
    await expectLater(HelperOpener.resolveTrailerVideo(null), throwsArgumentError);
  });

  test('preserves the original DMM URL and encodes proxy query parameters', () {
    const url = 'https://cc3001.dmm.co.jp/litevideo/freepv/e/eya/eyan00181/eyan00181_mhb_w.mp4?token=a%2Fb&expires=123';
    final urls = HelperOpener.trailerUrls(' $url ');
    expect(urls.first, url);
    expect(urls, hasLength(2));
    final proxy = Uri.parse(urls.last);
    expect(proxy.queryParameters['video'], url);
    expect(proxy.queryParameters.keys, ['video']);
    expect(urls.last, startsWith(Env.vidUrl));
    expect(HelperOpener.trailerUrls(urls.last), [urls.last]);
  });

  test('keeps supplied HLS URLs and rejects malformed or local URLs', () {
    const url = 'https://example.com/playlist.m3u8';
    expect(HelperOpener.trailerUrls(url).first, url);
    for (final invalid in ['', 'not a URL', 'file:///tmp/video.mp4', 'https:///video.mp4', 'https://user:password@example.com/video.mp4']) {
      expect(HelperOpener.trailerUrls(invalid), isEmpty);
    }
    final urls = HelperOpener.trailerUrls('https://example.com/preview.mp4');
    expect(urls.any((url) => url.contains('playlist.m3u8')), isFalse);
  });

  testWidgets('retries the proxy, cleans up failed players and allows another attempt', (tester) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _UnavailableTrailerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
      Get.reset();
    });
    await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(home: const Scaffold(body: SizedBox()))));
    const url = 'https://example.com/preview.mp4';
    for (var attempt = 0; attempt < 2; attempt++) {
      final opening = HelperOpener.openTrailer({'video_code': 'ABP-001', 'trailer': url});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await opening;
      expect(HomePanelAppLog.appLogRuntime.first.content, 'Unable to play trailer: Bad state: Source unavailable');
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(Get.isDialogOpen, isFalse);
    }
    expect(platform.sources, [...HelperOpener.trailerUrls(url), ...HelperOpener.trailerUrls(url)]);
    expect(platform.disposed, [1, 2, 3, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trailer fits the window, preserves its ratio and disposes on Close or Escape', (tester) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _AvailableTrailerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
      Get.reset();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(home: const Scaffold(body: SizedBox()))));
    for (final size in [const Size(1920, 1080), const Size(1080, 1920)]) {
      platform.size = size;
      final opening = HelperOpener.openTrailer({'video_code': 'ABP-001', 'title': 'Test title', 'trailer': 'https://example.com/preview.mp4'});
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('ABP-001'), findsWidgets);
      expect(find.text('Test title'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byWidgetPredicate((widget) => widget is DecoratedBox &&
        widget.decoration is BoxDecoration && (widget.decoration as BoxDecoration).color == Colors.black54), findsNothing);
      final playerSize = tester.getSize(find.byType(VideoPlayer));
      expect(playerSize.aspectRatio, closeTo(size.aspectRatio, .001));
      expect(tester.getRect(find.byType(Chewie)).bottom, lessThanOrEqualTo(584));
      tester.view.physicalSize = const Size(640, 400);
      await tester.pump();
      expect(tester.getRect(find.byType(Chewie)).bottom, lessThanOrEqualTo(384));
      expect(tester.takeException(), isNull);
      if (size.width > size.height) {
        await tester.tap(find.byTooltip('Close'));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      var closed = false;
      unawaited(opening.then((_) => closed = true));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byType(Chewie), findsNothing);
      expect(closed, isTrue, reason: 'Disposed: ${platform.disposed}, dialogs: ${Get.isDialogOpen}');
    }
    await tester.pump(const Duration(seconds: 16));
    expect(platform.disposed, [1, 2]);
    expect(tester.takeException(), isNull);
  });
}
