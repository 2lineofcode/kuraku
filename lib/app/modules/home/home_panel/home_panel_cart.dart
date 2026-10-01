import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../player/player_multi_view.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import 'home_panel_library.dart';
import 'home_panel_playlist.dart';

mixin HomePanelCart {
  static final _controller = Get.find<HomeController>();

  static Future<void> open() async {
    _controller.deduplicateCart();
    if (_controller.cart.isEmpty) return;

    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: VStack(
          [
            HStack(
              [
                Icon(UIconsPro.regularRounded.bags_shopping, size: 16).pOnly(right: 12, left: 8),
                Obx(() => 'Video Cart (${_controller.cart.length})'.text.bold.make()),
                Spacer(),
                IconButton(
                  icon: Icon(UIconsPro.regularRounded.delete, size: 13).tooltip('Empty Cart'),
                  onPressed: () async {
                    _controller.cart.value = [];
                    await Overlayment.dismissLast();
                  },
                ),
              ],
            ),
            Divider(),
            Obx(
              () => _controller.cart.isEmpty
                  ? ExUiErrorOrEmpty(illustration: Icon(UIconsPro.regularRounded.empty_set, size: 64).pOnly(bottom: 12), message: 'Cart is empty').expand()
                  : ListView.separated(
                      itemCount: _controller.cart.length,
                      separatorBuilder: (context, index) => Divider(color: AppColor.border),
                      itemBuilder: (context, index) {
                        final __item = _controller.cart[index];

                        return Container(
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
                                ).onDoubleTap(() {
                                  Overlayment.dismissLast();
                                  HelperOpener.openVideoFile(__item);
                                }).cornerRadius(4),
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
                                  '${__item.filesize?.toFileSizeFormat()}'.text.orange300.size(11).minFontSize(11).make().pOnly(right: 8).tooltip('${__item.videoPath}'),
                                ]).pOnly(top: 8),
                              ]).h(110).expand(),
                              VStack(
                                [
                                  IconButton(
                                    icon: Icon(UIconsPro.regularRounded.minus_circle, size: 14),
                                    onPressed: () {
                                      _controller.cart.removeAt(index);
                                      _controller.cart.refresh();
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(UIconsPro.regularRounded.trash, size: 14, color: Vx.red500),
                                    onPressed: () async {
                                      await _deleteVideo(__item);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ).p8(),
                        );
                      },
                    ).expand(),
            ),
            Divider(),


            // !! action
            HStack(
              [

                Spacer(),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: IconButton(
                    icon: Icon(UIconsPro.regularRounded.trash, size: 16, color: Vx.red300),
                    onPressed: () async {
                      await _deleteVideos(_controller.cart);
                    },
                  ),
                ).pOnly(right: 8).tooltip('Delete All This Files'),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: HStack([
                    Icon(UIconsPro.regularRounded.play, size: 14)
                  ]).p(10).pSymmetric(h: 12),
                ).onInkTap(() => _playVideos()).pOnly(right: 8).tooltip('Play as Playlist'),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: HStack([
                    Icon(UIconsPro.regularRounded.camera_movie, size: 14)
                  ]).p(10).pSymmetric(h: 12),
                ).onInkTap(() => _openInGridPlayer()).pOnly(right: 8).tooltip('Open in Grid Player'),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: IconButton(
                    icon: Icon(UIconsPro.regularRounded.list_check, size: 16, color: Vx.orange300),
                    onPressed: () async {
                      // await Overlayment.dismissLast();
                      await HomePanelPlaylist.showDialogAddToPlaylistItem(_controller.cart);
                    },
                  ),
                ).pOnly(right: 8).tooltip('Add to Playlist'),

                Spacer(),
              ],
            ),
          ],
        ).p8(),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ! Delete Video
  // ────────────────────────────────────────────────────────────────
  static Future<void> _deleteVideo(Videos videos) async {
    await Overlayment.dismissLast();
    ExAlert.adaptive(
      isDismissible: false,
      title: Text('Are you sure?', style: TextStyle(fontSize: 14)),
      content: Text('Delete "${videos.title}"? this action can\'t be undo', style: TextStyle(fontSize: 12)).pOnly(top: 8),
      actions: [
        CupertinoDialogAction(
          child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
          onPressed: () async {
            Get.back();

            if (videos.videoPath.isNotEmptyAndNotNull) {
              try {
                File(videos.videoPath!).deleteSync();
              } catch (e) {
                AppLog.logE('Failed to delete video ${videos.videoPath}: $e');
                await HelperToast.error('Failed to delete video: ${videos.videoPath}');
              }
              _controller.cart.remove(videos);
              _controller.cart.refresh();
              await open();
            }
            await _refreshState();
          },
        ),
        CupertinoDialogAction(
          child: Text('No', style: TextStyle(fontSize: 13)),
          onPressed: () async => {Get.back(), await open()}, 
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ! Delete Videos
  // ────────────────────────────────────────────────────────────────
  static Future<void> _deleteVideos(List<Videos> videos) async {
    await Overlayment.dismissLast();

    ExAlert.adaptive(
      title: Text('Are you sure?', style: TextStyle(fontSize: 14)),
      content: Text('Delete this video files? this action can\'t be undo', style: TextStyle(fontSize: 12)).pOnly(top: 8),
      actions: [
        CupertinoDialogAction(
          child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
          onPressed: () async {
            Get.back();
            final fileToDelete = videos.map((e) => e.videoPath).toList();
            for (var file in fileToDelete) {
              AppLog.logW('delete video: $file');

              if (file.isNotEmptyAndNotNull) {
                try {
                  File(file!).deleteSync();
                } catch (e) {
                  AppLog.logE('Failed to delete video $file: $e');
                  await HelperToast.error('Failed to delete video: $file');
                }
              }
            }

            await HelperToast.warn('${_controller.cart.length} Video deleted');
            await _refreshState();
          },
        ),
        CupertinoDialogAction(
          child: Text('No', style: TextStyle(fontSize: 13)),
          onPressed: () => Get.back(),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ? Play Videos
  // ────────────────────────────────────────────────────────────────
  static Future<void> _playVideos() async {
    final playableVideos = _controller.cart.where((video) {
      final path = (video.videoPath ?? '').trim();
      if (path.isEmpty) return false;
      return File(path).existsSync();
    }).toList();

    if (playableVideos.isEmpty) {
      await HelperToast.warn('No playable video found. Check your external drive connection.');
      return;
    }

    await Overlayment.dismissLast();
    await HelperOpener.openVideoFile(playableVideos.first, playlist: playableVideos);
  }

  static Future<void> _openInGridPlayer() async {
    await Overlayment.dismissLast();
    await Get.to(() => const PlayerMultiView(), arguments: _controller.cart.toList());

  }

  // ────────────────────────────────────────────────────────────────
  // * Refresh State
  // ────────────────────────────────────────────────────────────────
  static Future<void> _refreshState() async {
    _controller.cart.clear();
    await 300.milliseconds.delay();
    await HomePanelLibrary.doRescanAllVideoFromLibrary(_controller.library);
  }

}
