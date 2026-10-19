import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// DropItem.dataReader exposes this type from super_drag_and_drop's dependency.
// ignore: depend_on_referenced_packages
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:toastification/toastification.dart';

class _DropReader implements DataReader {
  final uri = Completer<Uri>();
  bool providesFileUri = true;

  @override
  bool canProvide(DataFormat format) => providesFileUri;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getValue) {
      uri.future.then(
        (value) => Function.apply(invocation.positionalArguments[1] as Function, [value]),
        onError: (Object error) => Function.apply(invocation.namedArguments[#onError] as Function, [error]),
      );
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _DropItem extends Fake with Diagnosticable implements DropItem {
  _DropItem(this.dataReader);
  @override
  final DataReader dataReader;
}

class _DropSession extends Fake with Diagnosticable implements DropSession {
  _DropSession(this.items);
  @override
  final List<DropItem> items;
}

class _Player implements Player {
  final opened = <Media>[];
  bool failOpen = false;
  Completer<void>? opening;
  Completer<void>? openStarted;
  int stops = 0;
  int disposals = 0;
  double? lastVolume;
  double? lastRate;
  @override
  PlatformPlayer? platform;
  @override
  PlayerState state = const PlayerState();

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failOpen) throw StateError('Unreadable video');
    opened.add(playable as Media);
    openStarted?.complete();
    openStarted = null;
    await opening?.future;
  }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> setRate(double rate) async { lastRate = rate; }
  @override
  Future<void> setVolume(double volume) async { lastVolume = volume; }
  @override
  Future<void> dispose() async { disposals++; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController implements VideoController {
  @override
  Future<void> get waitUntilFirstFrameRendered async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends StandalonePlayerController {
  final fakePlayer = _Player();
  Completer<void>? overlay;
  bool failInitialization = false;
  Completer<void>? initializing;
  Completer<void>? initializationStarted;
  @override
  Future<void> initializePlayer() async {
    player = fakePlayer;
    initializationStarted?.complete();
    await initializing?.future;
    if (failInitialization) throw StateError('Native video setup failed');
    videoController = _VideoController();
  }
  @override
  Future<void> showInfoOverlay(String text) async { await overlay?.future; }
}

void main() {
  late Directory directory;
  late _Controller controller;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('kuraku-playback-');
    addTearDown(() => directory.deleteSync(recursive: true));
  });
  tearDown(() {
    toastification.dismissAll(delayForAnimation: false);
    Get.reset();
  });

  Videos video(String name) {
    final file = File('${directory.path}/$name')..writeAsStringSync('fixture');
    return Videos(id: name, videoPath: file.path);
  }

  void standaloneTest(String description, Future<void> Function() body) {
    test(description, () async {
      controller = _Controller()..onStart();
      try {
        await body();
      } finally {
        await controller.onClose();
      }
    });
  }

  standaloneTest('standalone opens files and advances its playlist without a database service', () async {
    expect(Get.isRegistered<DBService>(), isFalse);
    final first = video('first #1.mp4');
    final second = video('second %20.mkv');
    await controller.openFiles([first.videoPath!, second.videoPath!, first.videoPath!]);
    expect(controller.playlist, hasLength(2));
    expect(controller.currentVideo.value.title, 'first #1');
    expect(controller.currentVideo.value.videoCode, isNull);
    expect(controller.fakePlayer.opened.single.uri, first.videoPath);
    expect(controller.isPlayerVisible.value, isTrue);
    await controller.nextVideo();
    expect(controller.currentVideo.value.videoPath, second.videoPath);
    expect(controller.currentIndexPlaying.value, 1);
    await controller.stopPlayback();
    expect(controller.playlist, isEmpty);
    expect(controller.isPlayerVisible.value, isFalse);
    expect(Get.isRegistered<DBService>(), isFalse);

    await controller.shutdown();
    await controller.shutdown();
  });

  standaloneTest('standalone playback settings stay in memory without a settings or database service', () async {
    expect(Get.isRegistered<AppSettingService>(), isFalse);
    expect(Get.isRegistered<DBService>(), isFalse);
    final initialVolume = controller.volume.value;
    final initialRate = controller.playbackSpeed.value;
    expect(await controller.startPlayback(video('settings.mp4')), isTrue);
    await controller.setVolumeNormalized(2);
    await controller.setPlaybackRate(99);
    await controller.applyAudioNormalization(enabled: true);
    expect(controller.volume.value, 1);
    expect(controller.fakePlayer.lastVolume, 100);
    expect(controller.playbackSpeed.value, 3);
    expect(controller.fakePlayer.lastRate, 3);
    expect(controller.isAudioNormalizationEnabled.value, isTrue);
    await controller.applyAudioNormalization(enabled: false);
    expect(controller.isAudioNormalizationEnabled.value, isFalse);
    final fresh = _Controller();
    expect(fresh.volume.value, initialVolume);
    expect(fresh.playbackSpeed.value, initialRate);
    expect(Get.isRegistered<AppSettingService>(), isFalse);
    expect(Get.isRegistered<DBService>(), isFalse);
  });

  standaloneTest('standalone drop keeps item order when file readers complete in reverse order', () async {
    expect(Get.isRegistered<DBService>(), isFalse);
    final first = video('first.mp4');
    final second = video('second.mp4');
    final readers = [_DropReader(), _DropReader(), _DropReader()];
    final playing = controller.isPlayerVisible.stream.firstWhere((visible) => visible);
    final drop = controller.onDropEvent(PerformDropEvent(
      session: _DropSession(readers.map(_DropItem.new).toList()),
      position: DropPosition(local: Offset.zero, global: Offset.zero),
      acceptedOperation: DropOperation.copy,
    ));
    readers[2].uri.complete(Uri.file(first.videoPath!));
    readers[1].uri.complete(Uri.file(second.videoPath!));
    readers[0].uri.complete(Uri.file(first.videoPath!));
    await drop;
    await playing;
    expect(controller.playlist.map((item) => item.videoPath), [first.videoPath, second.videoPath]);
    expect(controller.currentVideo.value.videoPath, first.videoPath);
  });

  standaloneTest('14-file drop releases the native callback before loading playback', () async {
    final videos = List.generate(14, (index) => video('video $index #%.mp4'));
    final readers = videos.map((_) => _DropReader()).toList();
    final opening = Completer<void>();
    final openStarted = Completer<void>();
    controller.fakePlayer.opening = opening;
    controller.fakePlayer.openStarted = openStarted;
    final playing = controller.isPlayerVisible.stream.firstWhere((visible) => visible);
    try {
      final drop = controller.onDropEvent(PerformDropEvent(
        session: _DropSession(readers.map(_DropItem.new).toList()),
        position: DropPosition(local: Offset.zero, global: Offset.zero),
        acceptedOperation: DropOperation.copy,
      ));
      for (var index = readers.length - 1; index >= 0; index--) {
        readers[index].uri.complete(Uri.file(videos[index].videoPath!));
      }
      await drop.timeout(const Duration(seconds: 1));
      expect(controller.fakePlayer.opened, isEmpty, reason: 'native drop must finish before opening files');
      await openStarted.future;
      expect(controller.isPlayerVisible.value, isFalse);
      await Future<void>.delayed(Duration.zero);
      opening.complete();
      await playing;
      expect(controller.playlist.map((item) => item.videoPath), videos.map((item) => item.videoPath));
      expect(controller.fakePlayer.opened, hasLength(1));
      expect(Get.isRegistered<DBService>(), isFalse);
    } finally {
      if (!opening.isCompleted) opening.complete();
    }
  });

  standaloneTest('stop cancels a drop queued after the native callback returns', () async {
    final reader = _DropReader();
    final item = video('queued.mp4');
    reader.uri.complete(Uri.file(item.videoPath!));
    await controller.onDropEvent(PerformDropEvent(
      session: _DropSession([_DropItem(reader)]),
      position: DropPosition(local: Offset.zero, global: Offset.zero),
      acceptedOperation: DropOperation.copy,
    ));
    await controller.stopPlayback();
    await Future<void>(() {});
    expect(controller.fakePlayer.opened, isEmpty);
    expect(controller.playlist, isEmpty);
  });

  standaloneTest('an unreadable drop item does not block the remaining files', () async {
    final item = video('readable.mp4');
    final readers = [_DropReader(), _DropReader(), _DropReader()..providesFileUri = false];
    final playing = controller.isPlayerVisible.stream.firstWhere((visible) => visible);
    final drop = controller.onDropEvent(PerformDropEvent(
      session: _DropSession(readers.map(_DropItem.new).toList()),
      position: DropPosition(local: Offset.zero, global: Offset.zero),
      acceptedOperation: DropOperation.copy,
    ));
    readers.first.uri.completeError(StateError('File unavailable'));
    readers[1].uri.complete(Uri.file(item.videoPath!));
    await drop.timeout(const Duration(seconds: 1));
    await playing;
    expect(controller.playlist.single.videoPath, item.videoPath);
  });

  for (final action in ['open', 'next']) {
    standaloneTest('stop cancels a pending $action without restoring playback', () async {
      final first = video('first.mp4');
      final second = video('second.mp4');
      expect(await controller.startPlayback(first, playlist: [first, second]), isTrue);
      final opening = Completer<void>();
      controller.fakePlayer.opening = opening;
      final openStarted = Completer<void>();
      controller.fakePlayer.openStarted = openStarted;
      final pending = action == 'open' ? controller.startPlayback(second) : controller.nextVideo();
      await openStarted.future;
      expect(controller.fakePlayer.opened, hasLength(2));
      await controller.stopPlayback();
      opening.complete();
      await pending;
      expect(controller.isPlayerVisible.value, isFalse);
      expect(controller.currentVideo.value.videoPath, isNull);
      expect(controller.playlist, isEmpty);
      expect(controller.status.isLoading, isTrue);
      controller.fakePlayer.opening = null;
      expect(await controller.startPlayback(first), isTrue);
      expect(controller.isPlayerVisible.value, isTrue);
    });
  }

  standaloneTest('stop cancels a drop whose file reader is still pending', () async {
    final first = video('first.mp4');
    final second = video('second.mp4');
    expect(await controller.startPlayback(first), isTrue);
    final reader = _DropReader();
    final drop = controller.onDropEvent(PerformDropEvent(
      session: _DropSession([_DropItem(reader)]),
      position: DropPosition(local: Offset.zero, global: Offset.zero),
      acceptedOperation: DropOperation.copy,
    ));
    await controller.stopPlayback();
    reader.uri.complete(Uri.file(second.videoPath!));
    await drop;
    expect(controller.fakePlayer.opened, hasLength(1));
    expect(controller.isPlayerVisible.value, isFalse);
    expect(controller.playlist, isEmpty);
  });

  standaloneTest('standalone shutdown prevents a pending open from publishing playback', () async {
    expect(Get.isRegistered<DBService>(), isFalse);
    final item = video('pending.mp4');
    final opening = Completer<void>();
    controller.fakePlayer.opening = opening;
    final openStarted = Completer<void>();
    controller.fakePlayer.openStarted = openStarted;
    final playback = controller.startPlayback(item);
    await openStarted.future;
    await controller.shutdown();
    opening.complete();
    expect(await playback, isFalse);
    expect(controller.isPlayerVisible.value, isFalse);
    expect(controller.currentVideo.value.videoPath, isNull);
    expect(await controller.startPlayback(item), isFalse);
  });

  standaloneTest('shutdown disposes a player whose pending video initialization fails', () async {
    controller.failInitialization = true;
    final initializing = Completer<void>();
    final initializedPlayer = Completer<void>();
    controller.initializing = initializing;
    controller.initializationStarted = initializedPlayer;
    final playback = controller.startPlayback(video('init-failure.mp4'));
    await initializedPlayer.future;
    final shutdown = controller.shutdown();
    initializing.complete();
    expect(await playback, isFalse);
    await shutdown;
    await controller.shutdown();
    expect(controller.fakePlayer.disposals, 1);
  });

  standaloneTest('standalone single-file playback never loads neighboring library files', () async {
    expect(Get.isRegistered<DBService>(), isFalse);
    final item = video('only.mp4');
    expect(await controller.startPlayback(item), isTrue);
    expect(controller.playlist, [item]);
    expect(controller.currentIndexPlaying.value, 0);
  });
}
