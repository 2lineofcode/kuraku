import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../player/player_multi_view.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
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
                HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, size: AppStyle.iconSize).pOnly(right: 12, left: 8),
                Obx(() => 'Video Cart (@{length})'.trNamed({'length': '${_controller.cart.length}'}).text.bold.make()),
                Spacer(),
                AppIconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize).tooltip('Empty Cart'.tr),
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
                  ? ExUiErrorOrEmpty(illustration: HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, size: AppStyle.emptyIconSize).pOnly(bottom: 12), message: 'Cart is empty'.tr).expand()
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
                                  AppIconButton(
                                    icon: HugeIcon(icon: HugeIcons.strokeRoundedRemoveCircle, size: AppStyle.iconSize),
                                    onPressed: () {
                                      _controller.cart.removeAt(index);
                                      _controller.cart.refresh();
                                    },
                                  ),
                                  AppIconButton(
                                    icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize, color: Vx.red500),
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
                  child: AppIconButton(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize, color: Vx.red300),
                    onPressed: () async {
                      await _deleteVideos(_controller.cart);
                    },
                  ),
                ).pOnly(right: 8).tooltip('Delete All This Files'.tr),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: HStack([
                    HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: AppStyle.iconSize)
                  ]).p(10).pSymmetric(h: 12),
                ).onInkTap(() => _playVideos()).pOnly(right: 8).tooltip('Play as Playlist'.tr),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: HStack([
                    HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.iconSize)
                  ]).p(10).pSymmetric(h: 12),
                ).onInkTap(() => _openInGridPlayer()).pOnly(right: 8).tooltip('Open in Grid Player'.tr),

                Container(
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: AppIconButton(
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.iconSize, color: Vx.orange300),
                    onPressed: () async {
                      // await Overlayment.dismissLast();
                      await HomePanelPlaylist.showDialogAddToPlaylistItem(_controller.cart);
                    },
                  ),
                ).pOnly(right: 8).tooltip('Add to Playlist'.tr),

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
    AppConfirmDialog.show(
      isDismissible: false,
      title: Text('Are you sure?'.tr, style: TextStyle(fontSize: 14)),
      content: Text('Delete "@{title}"? this action can\'t be undo'.trNamed({'title': '${videos.title}'}), style: TextStyle(fontSize: 12)).pOnly(top: 8),
      actions: [
        AppDialogAction(
          child: Text('Yes'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
          onPressed: () async {
            Get.back();

            if (videos.videoPath.isNotEmptyAndNotNull) {
              try {
                File(videos.videoPath!).deleteSync();
              } catch (e) {
                AppLog.logE('Failed to delete video ${videos.videoPath}: $e');
                await HelperToast.error('Failed to delete video: @{videoPath}'.trNamed({'videoPath': '${videos.videoPath}'}));
              }
              _controller.cart.remove(videos);
              _controller.cart.refresh();
              await open();
            }
            await _refreshState();
          },
        ),
        AppDialogAction(
          child: Text('No'.tr, style: TextStyle(fontSize: 13)),
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

    AppConfirmDialog.show(
      title: Text('Are you sure?'.tr, style: TextStyle(fontSize: 14)),
      content: Text('Delete this video files? this action can\'t be undo'.tr, style: TextStyle(fontSize: 12)).pOnly(top: 8),
      actions: [
        AppDialogAction(
          child: Text('Yes'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
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
                  await HelperToast.error('Failed to delete video: @{file}'.trNamed({'file': '$file'}));
                }
              }
            }

            await HelperToast.warn('@{length} Video deleted'.trNamed({'length': '${_controller.cart.length}'}));
            await _refreshState();
          },
        ),
        AppDialogAction(
          child: Text('No'.tr, style: TextStyle(fontSize: 13)),
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
      await HelperToast.warn('No playable video found. Check your external drive connection.'.tr);
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
