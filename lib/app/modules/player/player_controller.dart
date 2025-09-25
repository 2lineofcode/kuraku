import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart';
import 'package:process_run/stdio.dart';
import 'package:uicons_pro/uicons_pro.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';
import '../home/page_home/page_home_controller.dart';
import '../home/page_search/page_search_overlay.dart';
import '../widgets/widget_chiwie_custom.dart';
import '../widgets/widget_thumbnail.dart';

class PlayerController extends GetxController with StateMixin<Videos>, GetSingleTickerProviderStateMixin, WindowListener {
  final count = 0.obs;
  final fnMain = FocusNode();

  late CachedVideoPlayerPlus cachePlayer;
  late ChewieController chewie;

  final currentVideo = Videos().obs;
  final currentIndexPlaying = 0.obs;
  final playlist = <Videos>[].obs;

  final isFullScreen = false.obs;
  final infoOverlayText = ''.obs;
  late AnimationController infoAnimationController;

  @override
  Future<void> onInit() async {
    super.onInit();

    infoAnimationController = AnimationController(vsync: this, duration: 1.seconds, reverseDuration: 200.milliseconds);

    currentVideo.value = Get.arguments as Videos;
    await DBVideos.updateViewCount(currentVideo.value);
    await generatePlaylist();
    currentIndexPlaying.value = playlist.indexWhere((element) => element.id == currentVideo.value.id);

    try {
      cachePlayer = CachedVideoPlayerPlus.file(
        File(currentVideo.value.videoPath!),
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );

      await cachePlayer.initialize().then((_) async {
        await cachePlayer.controller.play();
        await cachePlayer.controller.setPlaybackSpeed(AppPref.getPlayerSpeed());
        await cachePlayer.controller.setVolume(AppPref.getPlayerVolume());
      });
    } catch (_) {}

    chewie = ChewieController(
      videoPlayerController: cachePlayer.controller,
      autoPlay: true,
      allowFullScreen: true,
      showOptions: false,
      zoomAndPan: true,
      allowMuting: true,
      autoInitialize: true,
      looping: false,
      customControls: ExChewieCustom(video: currentVideo.value, showTitle: true),
    );

    windowManager.addListener(this);
    change(currentVideo.value, status: RxStatus.success());
  }

  Future<void> generatePlaylist() async {
    playlist.clear();
    final list = await DBVideos.getAllVideoPath('video_path', '${dirname(currentVideo.value.videoPath!)}%');
    playlist.addAll(list);
    currentIndexPlaying.value = playlist.indexWhere((element) => element.id == currentVideo.value.id);
  }

  Future<void> openInfo() async {
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      return;
    }
    await PageSearchOverlay.onItemTap(currentVideo.value);
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

    _videos.value = await DBVideos.getAllVideoPath(
      'video_path',
      '${dirname(currentVideo.value.videoPath!)}%',
    );

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
            await _listScrollController.animateTo(currentIndexPlaying.value * 127, duration: 300.milliseconds, curve: Curves.decelerate);
            _fnSearch.requestFocus();
          },
          onClose: (p0) async{
            _fnSearch.unfocus();
          },
        ),
        child: VStack(
          [
            // 'Search'.text.make(),
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

                  await _listScrollController.animateTo(currentIndexPlaying.value * 127, duration: 300.milliseconds, curve: Curves.decelerate);
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
                          
                          // isHasUncensored
                          if (__item.videoPath?.isHasUncensored() == true) ...[
                            'RM'.text.red400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                          ],

                          // isHasEnSub
                          if (__item.videoPath?.isHasEnSub() == true) ...[
                            'EN'.text.blue400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                          ],

                          // isHasIdSub
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
                            GetBuilder(
                              init: PlayerController(),
                              builder: (c) => Icon(
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
                                update();
                              }),
                            ).pOnly(right: 12),
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
  }

  Future<void> changeVideo(Videos newVideo) async {
    currentVideo.value = newVideo;
    await cachePlayer.dispose();
    chewie.dispose();

    try {
      if (newVideo.videoPath == null) {
        await HelperToast.error('Video path is null');
        return;
      }

      cachePlayer = CachedVideoPlayerPlus.file(
        File(newVideo.videoPath!),
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );

      await cachePlayer.initialize().then((_) async {
        await cachePlayer.controller.play();
        await cachePlayer.controller.setPlaybackSpeed(1);
        await cachePlayer.controller.setVolume(0.1);
      });
    } catch (e) {
      await HelperToast.error('Failed to load new video: $e');
      return;
    }

    chewie = ChewieController(
      videoPlayerController: cachePlayer.controller,
      autoPlay: true,
      allowFullScreen: false,
      showOptions: false,
      zoomAndPan: true,
      allowMuting: true,
      autoInitialize: true,
      looping: false,
      customControls: ExChewieCustom(video: newVideo),
    );

    await generatePlaylist();
    await showInfoOverlay('${currentIndexPlaying.value + 1}/${playlist.length}');

    await DBVideos.updateViewCount(currentVideo.value);
    change(newVideo, status: RxStatus.success());
  }

  // ** shortcuts actions ** //
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

  Future<void> openSS() async {
    await HelperOpener.openScreenshot(currentVideo.value);
  }

  // ** end shortcuts actions ** //

  @override
  void onWindowEnterFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    isFullScreen.value = true;
  }

  @override
  void onWindowLeaveFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    isFullScreen.value = false;
  }

  @override
  Future<void> onClose() async {
    await cachePlayer.dispose();
    chewie.dispose();
    infoAnimationController.dispose();
    windowManager.removeListener(this);
    super.onClose();
  }
}
