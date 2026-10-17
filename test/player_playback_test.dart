import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:toastification/toastification.dart';

import 'chat_test_database.dart';

class _Database extends ChatTestDatabase {
  final views = <String, int>{};
  bool failViews = false;
  bool failPlaylist = false;
  Completer<void>? playlistQuery;
  List<Map<String, Object?>> playlistRows = [];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('FROM relapse_event')) return [{'times': 0}];
    if (sql.contains('ORDER BY video_code ASC, title ASC')) {
      await playlistQuery?.future;
      if (failPlaylist) throw StateError('Playlist unavailable');
      return playlistRows;
    }
    return super.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    if (failViews) throw StateError('Disk full');
    final id = arguments!.single as String;
    views[id] = (views[id] ?? 0) + 1;
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (table == 'videos') return [{'view_count': views[whereArgs!.single]}];
    return super.query(table, where: where, whereArgs: whereArgs);
  }
}

class _Player implements Player {
  final opened = <Media>[];
  bool failOpen = false;
  Completer<void>? opening;
  int stops = 0;
  @override
  PlatformPlayer? platform;
  @override
  PlayerState state = const PlayerState();

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failOpen) throw StateError('Unreadable video');
    opened.add(playable as Media);
    await opening?.future;
  }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController implements VideoController {
  @override
  Future<void> get waitUntilFirstFrameRendered async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends PlayerController {
  final fakePlayer = _Player();
  Completer<void>? overlay;
  @override
  Future<void> initializePlayer() async {
    player = fakePlayer;
    videoController = _VideoController();
  }
  @override
  Future<void> showInfoOverlay(String text) async { await overlay?.future; }
}

void main() {
  late Directory directory;
  late _Database database;
  late _Controller controller;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('kuraku-playback-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Get.put<AppSettingService>(AppSettingService()..pref = ChatTestPreferences());
    database = _Database();
    Get.put<DBService>(ChatTestService()..dbMain = database);
  });
  tearDown(() {
    toastification.dismissAll(delayForAnimation: false);
    Get.reset();
  });

  Videos video(String name) {
    final file = File('${directory.path}/$name')..writeAsStringSync('fixture');
    return Videos(id: name, videoPath: file.path);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: GetMaterialApp(home: const Scaffold(body: Text('Player'))),
    ));
  }

  void playbackTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      controller = _Controller()..onStart();
      try {
        await body(tester);
      } finally {
        await tester.pump();
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await controller.onClose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  playbackTest('playback preserves raw filesystem names when opening file URIs', (tester) async {
    await pump(tester);
    for (final name in ['Video #1.mp4', 'Video %20.mp4', if (!Platform.isWindows) 'Video ?1.mp4']) {
      final item = video(name);
      expect(await controller.startPlayback(item, playlist: [item]), isTrue);
      expect(controller.fakePlayer.opened.last.uri, item.videoPath);
      expect(controller.currentVideo.value, same(item));
      expect(database.views[item.id], 1);
      expect(controller.isPlayerVisible.value, isTrue);
    }
  });

  playbackTest('overlapping Next requests open and count a video only once', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final second = video('second.mp4');
    expect(await controller.startPlayback(first, playlist: [first, second]), isTrue);
    final opening = Completer<void>();
    controller.fakePlayer.opening = opening;
    final next = controller.nextVideo();
    await tester.pump();
    await controller.nextVideo();
    expect(controller.currentVideo.value, same(first));
    expect(controller.fakePlayer.opened, hasLength(2));
    opening.complete();
    await next;
    expect(controller.currentVideo.value, same(second));
    expect(controller.currentIndexPlaying.value, 1);
    expect(database.views, {first.id: 1, second.id: 1});
  });

  playbackTest('view count write failures keep successfully opened playback visible and usable', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final second = video('second.mp4');
    database.failViews = true;
    expect(await controller.startPlayback(first, playlist: [first, second]), isTrue);
    expect(controller.currentVideo.value, same(first));
    expect(controller.isPlayerVisible.value, isTrue);
    expect(controller.status.isSuccess, isTrue);
    expect(controller.fakePlayer.opened, hasLength(1));
    await controller.nextVideo();
    expect(controller.currentVideo.value, same(second));
    expect(controller.currentIndexPlaying.value, 1);
    expect(controller.isPlayerVisible.value, isTrue);
    expect(controller.fakePlayer.opened, hasLength(2));
    expect(database.views, isEmpty);
  });

  playbackTest('playlist lookup failures keep opened playback visible with a single-video fallback', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    database.failPlaylist = true;
    expect(await controller.startPlayback(first), isTrue);
    expect(controller.fakePlayer.opened, hasLength(1));
    expect(controller.isPlayerVisible.value, isTrue);
    expect(controller.status.isSuccess, isTrue);
    expect(controller.playlist, [first]);
    expect(controller.currentIndexPlaying.value, 0);
  });

  playbackTest('pending playlist publication prevents reopening the same next video', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final second = video('second.mp4');
    database.playlistRows = [first.toJson(), second.toJson()];
    expect(await controller.startPlayback(first), isTrue);
    final query = Completer<void>();
    database.playlistQuery = query;
    final next = controller.nextVideo();
    try {
      await tester.pump();
      await controller.nextVideo();
      expect(controller.fakePlayer.opened, hasLength(2));
    } finally {
      query.complete();
      await next;
    }
    expect(controller.currentVideo.value.id, second.id);
    expect(controller.currentIndexPlaying.value, 1);
    expect(database.views, {first.id: 1, second.id: 1});
  });

  playbackTest('delayed overlays cannot overwrite newer playback state or count the wrong video', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final second = video('second.mp4');
    final third = video('third.mp4');
    expect(await controller.startPlayback(first, playlist: [first, second, third]), isTrue);
    final overlay = Completer<void>();
    controller.overlay = overlay;
    final secondPlayback = controller.nextVideo();
    await tester.pump();
    final thirdPlayback = controller.nextVideo();
    try {
      await tester.pump();
      expect(controller.currentVideo.value, same(third));
      expect(controller.state, same(third));
      expect(database.views, {first.id: 1, second.id: 1, third.id: 1});
    } finally {
      overlay.complete();
      await Future.wait([secondPlayback, thirdPlayback]);
    }
    expect(controller.state, same(third));
    expect(controller.currentIndexPlaying.value, 2);
  });

  playbackTest('missing playlist files preserve the active video, index and view counts', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final missing = video('missing.mp4');
    final last = video('last.mp4');
    final items = [first, missing, last];
    expect(await controller.startPlayback(first, playlist: items), isTrue);
    File(missing.videoPath!).deleteSync();
    await controller.nextVideo();
    expect(controller.currentVideo.value, same(first));
    expect(controller.currentIndexPlaying.value, 0);
    expect(controller.fakePlayer.opened, hasLength(1));
    expect(controller.fakePlayer.stops, 0);
    expect(database.views, {first.id: 1});
    await controller.changeVideo(last);
    expect(controller.currentVideo.value, same(last));
    expect(controller.currentIndexPlaying.value, 2);
    await controller.prevVideo();
    expect(controller.currentVideo.value, same(last));
    expect(controller.currentIndexPlaying.value, 2);
    expect(database.views, {first.id: 1, last.id: 1});
  });

  playbackTest('failed native opens never publish a new video or increment its view count', (tester) async {
    await pump(tester);
    final first = video('first.mp4');
    final broken = video('broken.mp4');
    expect(await controller.startPlayback(first, playlist: [first, broken]), isTrue);
    controller.fakePlayer.failOpen = true;
    await controller.nextVideo();
    expect(controller.currentVideo.value, same(first));
    expect(controller.currentIndexPlaying.value, 0);
    expect(controller.isInitialized.value, isFalse);
    expect(controller.fakePlayer.stops, 1);
    expect(await controller.startPlayback(broken, playlist: [broken]), isFalse);
    expect(controller.currentVideo.value, same(first));
    expect(controller.currentIndexPlaying.value, 0);
    expect(database.views, {first.id: 1});
    controller.fakePlayer.failOpen = false;
    await controller.nextVideo();
    expect(controller.currentVideo.value, same(broken));
    expect(controller.currentIndexPlaying.value, 1);
    expect(database.views, {first.id: 1, broken.id: 1});
  });
}
