import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../env.g.dart';
import '../../core/app_color.dart';
import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';
import '../home/page_home/page_home_controller.dart';
import '../home/page_search/page_search_overlay.dart';
import '../widgets/widget_thumbnail.dart';

class PlayerController extends GetxController with StateMixin<Videos>, GetSingleTickerProviderStateMixin {
  final count = 0.obs;
  final fnMain = FocusNode();
  final focusSignal = 0.obs;
  final videoKey = GlobalKey<VideoState>();

  late final Player player;
  late final VideoController videoController;

  final currentVideo = Videos().obs;
  final currentIndexPlaying = 0.obs;
  final playlist = <Videos>[].obs;

  final isInitialized = false.obs;
  final isFullScreen = false.obs;
  final infoOverlayText = ''.obs;
  final videoFit = BoxFit.contain.obs;

  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final volume = AppPref.getPlayerVolume().obs;
  final playbackSpeed = AppPref.getPlayerSpeed().obs;
  final bufferingPercent = 0.0.obs;

  late AnimationController infoAnimationController;

  final _subscriptions = <StreamSubscription>[];
  double _lastPersistedVolume = AppPref.getPlayerVolume();
  double _lastPersistedSpeed = AppPref.getPlayerSpeed();
  bool _hasSyncedPreferences = false;

  final args = Get.arguments as List;
  late final List<Videos>? _argumentPlaylist = _parseArgumentPlaylist();
  final isHasPlaylistBefore = false.obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    player = Player(
      configuration: PlayerConfiguration(
        vo: 'libmpv',
        logLevel: MPVLogLevel.debug,
        title: Env.appName,
        ready: () => AppLog.logD('player is ready'),
      ),
    );

    if (player.platform is NativePlayer) {
      final p = player.platform as NativePlayer;
      await p.setProperty('vo', 'libmpv');
      await p.setProperty('hwdec', 'auto-safe');
      await p.setProperty('opengl-hwdec-interop', 'auto');

      await p.setProperty('video-sync', 'display-resample');
      await p.setProperty('interpolation', 'no');
      await p.setProperty('framedrop', 'decoder+vo');
      await p.setProperty('autosync', '0');
      await p.setProperty('correct-pts', 'yes');
      await p.setProperty('demuxer-thread', 'yes');      
      
      //
      await p.setProperty('hr-seek', 'no');
      await p.setProperty('hr-seek-demuxer', 'yes');
      await p.setProperty('hr-seek-framedrop', 'yes');

      //
      await p.setProperty('cache', 'auto');
      await p.setProperty('cache-secs', '60');
      await p.setProperty('cache-pause', 'no');
      await p.setProperty('demuxer-readahead-secs', '5');
      await p.setProperty('demuxer-lavf-o', 'seek_timestamp=1');

    }

    videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: 'libmpv',
        hwdec: 'auto-safe',
      ),
    );
    infoAnimationController = AnimationController(vsync: this, duration: 1.seconds, reverseDuration: 200.milliseconds);

    _bindPlayerStreams();

    isHasPlaylistBefore.value = _argumentPlaylist != null;
    if (isHasPlaylistBefore.isFalse) {
      AppLog.logD('single mode');
      currentVideo.value = args[0] as Videos;
    } else {
      AppLog.logD('multiple mode');
      currentVideo.value = args[0] as Videos;
    }

    await DBVideos.updateViewCount(currentVideo.value);
    await generatePlaylist();
    currentIndexPlaying.value = playlist.indexWhere((element) => element.id == currentVideo.value.id);

    await _openVideo(currentVideo.value);

    change(currentVideo.value, status: RxStatus.success());
    requestFocusOnPlayer();
  }

  void _bindPlayerStreams() {
    _subscriptions.add(player.stream.position.listen((value) => position.value = value));
    _subscriptions.add(player.stream.duration.listen((value) => duration.value = value));
    _subscriptions.add(player.stream.playing.listen((value) => isPlaying.value = value));
    _subscriptions.add(player.stream.buffering.listen((value) => isBuffering.value = value));
    _subscriptions.add(player.stream.bufferingPercentage.listen((value) => bufferingPercent.value = value));

    _subscriptions.add(player.stream.volume.listen((value) {
      final normalized = (value / 100.0).clamp(0.0, 1.0);
      volume.value = normalized;
      if (_hasSyncedPreferences && (normalized - _lastPersistedVolume).abs() > 0.01) {
        _lastPersistedVolume = normalized;
        AppPref.setPlayerVolume(normalized);
      }
    }));

    _subscriptions.add(player.stream.rate.listen((value) {
      playbackSpeed.value = value;
      if (_hasSyncedPreferences && (value - _lastPersistedSpeed).abs() > 0.01) {
        _lastPersistedSpeed = value;
        AppPref.setPlayerSpeed(value);
      }
    }));

    _subscriptions.add(player.stream.width.listen((value) {
      if (value != null && value > 0) isInitialized.value = true;
    }));

    _subscriptions.add(player.stream.height.listen((value) {
      if (value != null && value > 0) isInitialized.value = true;
    }));

    _subscriptions.add(player.stream.error.listen((value) async {
      if (value.isNotEmpty) await HelperToast.error(value);
    }));
  }

  Future<void> _openVideo(Videos video) async {
    final path = video.videoPath;
    if (path.isNullOrEmpty) {
      await HelperToast.error('Video path is null');
      return;
    }

    final file = File(path!);
    if (!file.existsSync()) {
      await HelperToast.warn('Cant access video file');
      return;
    }

    try {
      isInitialized.value = false;
      _hasSyncedPreferences = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;

      await player.open(
        Media(Uri.file(path).toString()),
        play: true,
      );

      await player.setRate(playbackSpeed.value);
      await player.setVolume(volume.value * 100);
      _hasSyncedPreferences = true;
      try {
        await videoController.waitUntilFirstFrameRendered.timeout(3.seconds, onTimeout: () => null);
      } catch (_) {}
      isInitialized.value = true;
    } catch (e) {
      isInitialized.value = false;
      await HelperToast.error('Failed to load video: $e');
    }
  }

  Future<void> setVolumeNormalized(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    volume.value = normalized;
    _lastPersistedVolume = normalized;
    AppPref.setPlayerVolume(normalized);
    _hasSyncedPreferences = true;
    await player.setVolume(normalized * 100);
  }

  Future<void> adjustVolume(double delta) async {
    await setVolumeNormalized(volume.value + delta);
  }

  Future<void> mute() async {
    await setVolumeNormalized(0.0);
  }

  Future<void> setPlaybackRate(double value) async {
    final clamped = value.clamp(0.25, 3.0);
    playbackSpeed.value = clamped;
    _lastPersistedSpeed = clamped;
    AppPref.setPlayerSpeed(clamped);
    _hasSyncedPreferences = true;
    await player.setRate(clamped);
  }

  Future<void> adjustPlaybackRate(double delta) async {
    await setPlaybackRate(playbackSpeed.value + delta);
  }

  Future<void> togglePlayPause() async {
    if (isPlaying.value) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration target) async {
    final total = duration.value;
    final clamped = _clampDuration(
      target,
      Duration.zero,
      total > Duration.zero ? total : target,
    );

    final p = player.platform as NativePlayer;
    await p.seek(clamped, synchronized: true);
  }

  Future<void> seekRelative(Duration offset) async {
    final player = this.player;
    if (player.platform is NativePlayer) {
      final p = player.platform as NativePlayer;
      final seconds = offset.inSeconds.toString();
      await p.command(['seek', seconds, 'relative']); 
    } else {
      await seek(position.value + offset);
    }
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (max > min && value > max) return max;
    return value;
  }

  Future<void> generatePlaylist() async {
    playlist.clear();
    final initialPlaylist = _argumentPlaylist;
    if (initialPlaylist != null && initialPlaylist.isNotEmpty) {
      playlist.addAll(initialPlaylist);
    } else {
      final directoryVideos = await DBVideos.getAllVideoPath('video_path', '${dirname(currentVideo.value.videoPath!)}%');
      playlist.addAll(directoryVideos);
    }
    currentIndexPlaying.value = playlist.indexWhere((element) => element.id == currentVideo.value.id);
  }

  Future<void> openInfo() async {
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      requestFocusOnPlayer();
      return;
    }
    await PageSearchOverlay.onItemTap(currentVideo.value);
    requestFocusOnPlayer();
  }

  Future<void> openList() async {
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      return;
    }

    final _tecSearch = TextEditingController(text: '');
    final _fnSearch = FocusNode();
    final _videos = <Videos>[].obs;
    final _listScrollController = ScrollController();

    _videos.value = playlist;

    if (_listScrollController.hasClients) {
      _listScrollController.jumpTo(currentIndexPlaying.value * 135);
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        color: Colors.black12,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerRight,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        actions: OverlayActions(
          onReady: () async {
            await _listScrollController.animateTo(
              currentIndexPlaying.value * 127,
              duration: 300.milliseconds,
              curve: Curves.decelerate,
            );
            _fnSearch.requestFocus();
          },
          onClose: (p0) async {
            _fnSearch.unfocus();
            requestFocusOnPlayer();
          },
        ),
        child: VStack(
          [
            CupertinoTextField(
              controller: _tecSearch,
              focusNode: _fnSearch,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: 'Search (${_videos.length})...',
              style: TextStyle(color: Vx.white, fontSize: 14),
              prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
              onSubmitted: (q) async {
                if (q.isEmpty) {
                  _videos.value = await DBVideos.getAll(
                    where: 'video_path LIKE ?',
                    whereArgs: ['${dirname(currentVideo.value.videoPath!)}%'],
                  );

                  await _listScrollController.animateTo(
                    currentIndexPlaying.value * 127,
                    duration: 300.milliseconds,
                    curve: Curves.decelerate,
                  );
                } else {
                  _videos.value = await DBVideos.getAll(
                    where: 'video_code LIKE ? OR title LIKE ? OR video_path LIKE ?',
                    whereArgs: ['%$q%', '%$q%', '%$q%'],
                  );

                  _listScrollController.animToTop();
                }
              },
            ).pSymmetric(v: 12),
            Obx(
              () => ListView.separated(
                controller: _listScrollController,
                itemCount: _videos.length,
                separatorBuilder: (context, index) => Divider(color: AppColor.border),
                itemBuilder: (context, index) {
                  final __item = _videos[index];
                  final isSelected = __item.videoPath == currentVideo.value.videoPath;

                  return Container(
                    color: isSelected ? AppColor.selected : Colors.transparent,
                    child: HStack(
                      alignment: MainAxisAlignment.start,
                      crossAlignment: CrossAxisAlignment.start,
                      [
                        ZStack([
                          ExThumbnail(
                            imageUrl: '${__item.fanArt}',
                            videoPath: __item.videoPath,
                            width: 90,
                            height: 110,
                            prefix: 2.2,
                            fitUrl: BoxFit.fitWidth,
                          ).cornerRadius(4),
                          '${HelperMisc.formatVideoQuality(__item.quality ?? '').maxWords(1)}'
                              .text
                              .orange300
                              .size(11)
                              .minFontSize(11)
                              .make()
                              .pSymmetric(h: 4)
                              .color(AppColor.black170)
                              .cornerRadius(4)
                              .positioned(bottom: 3, left: 3),
                          if (__item.videoPath?.isHasUncensored() == true) ...[
                            'RM'.text.red400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                          ],
                          if (__item.videoPath?.isHasEnSub() == true) ...[
                            'EN'.text.blue400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                          ],
                          if (__item.videoPath?.isHasIdSub() == true) ...[
                            'ID'.text.blue400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                          ],
                        ]).pOnly(right: 12),
                        VStack([
                          '${__item.videoCode == '' ? __item.title?.maxWords(5) : __item.videoCode}'.text.bold.ellipsis.maxLines(1).minFontSize(13).size(13).make().pOnly(bottom: 12),
                          '${__item.title}'.text.minFontSize(12).size(12).maxLines(3).ellipsis.make(),
                          Spacer(),
                          HStack([
                            '${__item.filesize?.toFileSize()}'.text.orange300.size(11).minFontSize(11).make().pOnly(right: 8).tooltip('${__item.videoPath}'),
                            Spacer(),
                            Icon(
                              __item.isFavorite == 1 ? UIconsPro.solidRounded.star : UIconsPro.regularRounded.star,
                              color: __item.isFavorite == 1 ? Colors.orange : null,
                              size: 13,
                            ).onInkTap(() async {
                              if (__item.isFavorite == 1) {
                                __item.isFavorite = 0;
                                await DBVideos.removeFromFavorite(__item);
                              } else {
                                __item.isFavorite = 1;
                                await DBVideos.addToFavorite(__item);
                              }
                              await Get.find<PageHomeController>().onInit();
                              _videos.refresh();
                            }).pOnly(right: 12),
                            if (!__item.actress.isEmptyOrNull) ...[
                              Icon(UIconsPro.regularRounded.person_dolly, size: 13).pOnly(right: 8).onInkTap(() async {
                                final _fltr = await DBVideos.getByActress(__item.actress?[0].nameRomaji ?? '');
                                _videos.value = _fltr;
                                update();
                              }).tooltip(__item.actress?[0].nameRomaji ?? ''),
                            ],
                            if (__item.series.isNotEmptyAndNotNull) ...[
                              Icon(UIconsPro.regularRounded.tags, size: 13).pOnly(right: 8).onInkTap(() async {
                                final _fltr = await DBVideos.getBySeries(__item.series ?? '');
                                _videos.value = _fltr;
                                update();
                              }).tooltip(__item.series ?? ''),
                            ],
                          ]).pOnly(top: 8),
                        ]).h(110).expand(),
                      ],
                    ).onDoubleTap(() async {
                      if (isSelected) return;
                      await Overlayment.dismissLast();

                      final file = File(__item.videoPath!);
                      if (!file.existsSync()) {
                        await HelperToast.warn('Cant access video file');
                        return;
                      }

                      currentIndexPlaying.value = index;
                      await changeVideo(__item);
                    }).p8(),
                  );
                },
              ).expand(),
            ),
          ],
        ).p12(),
      ),
    );
    requestFocusOnPlayer();
  }

  Future<void> changeVideo(Videos newVideo) async {
    currentVideo.value = newVideo;
    await _openVideo(newVideo);
    await generatePlaylist();
    await showInfoOverlay('${currentIndexPlaying.value + 1}/${playlist.length}');

    await DBVideos.updateViewCount(currentVideo.value);
    change(newVideo, status: RxStatus.success());
    requestFocusOnPlayer();
  }

  Future<void> showInfoOverlay(String text) async {
    infoOverlayText.value = text;
    if (infoAnimationController.isAnimating || infoAnimationController.isCompleted) {
      infoAnimationController.reset();
    }
    await infoAnimationController.forward().then((_) async {
      await Future.delayed(1500.milliseconds);
      await infoAnimationController.reverse();
    });
  }

  Future<void> toggleVideoFit() async {
    videoFit.value = videoFit.value == BoxFit.contain ? BoxFit.fitHeight : BoxFit.contain;
    final label = videoFit.value == BoxFit.contain ? 'Fit: Contain' : 'Fit: Fit Height';
    await showInfoOverlay(label);
  }

  Future<void> nextVideo() async {
    if (currentIndexPlaying.value + 1 >= playlist.length) return;
    currentIndexPlaying.value++;
    await changeVideo(playlist[currentIndexPlaying.value]);
  }

  Future<void> prevVideo() async {
    if (currentIndexPlaying.value - 1 < 0) return;
    currentIndexPlaying.value--;
    await changeVideo(playlist[currentIndexPlaying.value]);
  }

  Future<void> toggleFullscreen() async {
    final state = videoKey.currentState;
    if (state == null) {
      AppLog.logD('toggleFullscreen: videoKey.currentState is null');
      return;
    }

    final isCurrentlyFullScreen = state.isFullscreen();
    AppLog.logD('toggleFullscreen: currently fullscreen = $isCurrentlyFullScreen');

    try {
      if (isCurrentlyFullScreen) {
        await state.exitFullscreen();
        isFullScreen.value = false;
        AppLog.logD('toggleFullscreen: exited fullscreen');
      } else {
        await state.enterFullscreen();
        isFullScreen.value = true;
        AppLog.logD('toggleFullscreen: entered fullscreen');
      }

      // Force app update for fullscreen transition per GetX requirements
      await Get.forceAppUpdate();

      // Wait for widget tree rebuild and focus restoration
      // The fullscreenSubscription in media_kit_controls will handle focus
      await Future.delayed(10.milliseconds);
    } catch (e) {
      AppLog.logD('toggleFullscreen error: $e');
    }
  }

  Future<void> openSS() async {
    await HelperOpener.openScreenshot(currentVideo.value);
  }

  @override
  Future<void> onClose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    infoAnimationController.dispose();
    fnMain.dispose();
    super.onClose();
  }

  void requestFocusOnPlayer() {
    focusSignal.value++;
    if (!fnMain.hasFocus) {
      fnMain.requestFocus();
    }
  }

  List<Videos>? _parseArgumentPlaylist() {
    if (args.length < 2) return null;
    final raw = args[1];
    if (raw is Iterable<Videos>) {
      return List<Videos>.from(raw);
    }
    return null;
  }
}
