// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/widgets/widget_chiwie_custom.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) => values[key] = value;

  @override
  Future<void> write(String key, dynamic value) async => writeInMemory(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal in-memory video platform so the custom Chewie controls can be
/// rendered without any native player.
class _FakeVideoPlayerPlatform with MockPlatformInterfaceMixin implements VideoPlayerPlatform {
  final controllerEvents = StreamController<VideoEvent>.broadcast();

  Duration position = Duration.zero;
  double volume = 1;
  double speed = 1;
  bool playing = false;
  int seeks = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 1;

  @override
  Future<void> dispose(int textureId) async {}

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> play(int textureId) async => playing = true;

  @override
  Future<void> pause(int textureId) async => playing = false;

  @override
  Future<void> setVolume(int textureId, double volume) async => this.volume = volume;

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async => this.speed = speed;

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    seeks++;
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int textureId) async => position;

  @override
  Widget buildView(int textureId) => const SizedBox.expand();

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) async* {
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 10),
      size: const Size(1920, 1080),
    );
    yield* controllerEvents.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createWithOptions) return Future<int?>.value(1);
    return Future<void>.value();
  }
}

void main() {
  late _FakeVideoPlayerPlatform platform;
  late _Preferences preferences;
  late VideoPlayerController videoController;
  late ChewieController chewieController;
  late Videos video;

  setUp(() async {
    platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    preferences = _Preferences();
    Get.put(AppSettingService()..pref = preferences);

    video = Videos(videoCode: 'ABP-001', title: 'A test movie', videoPath: '/movies/ABP-001.mp4');
    videoController = VideoPlayerController.networkUrl(Uri.parse('https://example.com/movie.mp4'));
    await videoController.initialize();
    chewieController = ChewieController(
      videoPlayerController: videoController,
      autoInitialize: false,
      autoPlay: false,
      showControlsOnInitialize: true,
      customControls: ExChewieCustom(video: video),
    );
  });

  tearDown(() async {
    chewieController.dispose();
    await videoController.dispose();
    await platform.controllerEvents.close();
    await Get.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Chewie(controller: chewieController)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the custom controls for an initialised video', (tester) async {
    await pump(tester);

    expect(find.byType(ExChewieCustom), findsOneWidget);
    expect(videoController.value.isInitialized, isTrue);
    expect(videoController.value.duration, const Duration(minutes: 10));
  });

  testWidgets('space toggles playback and announces the new state', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.playing, isTrue);
    expect(find.text('Playing'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.playing, isFalse);
    expect(find.text('Paused'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('arrow keys seek forward and backward and never leave the video', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.position, const Duration(seconds: 5));
    expect(find.textContaining('Forward:'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.position, Duration.zero, reason: 'seeking back before the start is clamped');
    expect(find.textContaining('Backward:'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('volume, mute and speed shortcuts update the player and the preferences', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.volume, closeTo(0.95, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.volume, closeTo(1, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.volume, 0);
    expect(preferences.values['_kPlayerVolume'], isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.speed, closeTo(1.1, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.speed, closeTo(1.0, 1e-9));
    expect(preferences.values['_kPlayerSpeed'], isNotNull);

    await tester.pumpAndSettle();
  });
}
