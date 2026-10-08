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
        width: Get.width < 360 ? Get.width : 360,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: Builder(builder: (context) {
          AppColor.dependOn(context);
          return Material(
            color: AppColor.panel,
            child: Padding(
              padding: const EdgeInsets.all(AppStyle.panelPadding),
              child: Obx(() {
                final items = _controller.cart.toList();
                final empty = items.isEmpty;
                final totalSize = items.fold<num>(0, (total, video) => total + (video.filesize ?? 0));
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, size: AppStyle.iconSize),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Video Cart (@{length})'.trNamed({'length': '${items.length}'}),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    AppIconButton(
                      tooltip: 'Empty Cart'.tr,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedRemoveCircle, size: AppStyle.iconSize),
                      onPressed: empty ? null : () async {
                        _controller.cart.clear();
                        await Overlayment.dismissLast();
                      },
                    ),
                    AppIconButton(
                      tooltip: 'Close'.tr,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize),
                      onPressed: () => Overlayment.dismissLast(),
                    ),
                  ]),
                  if (!empty) Text(totalSize.toFileSizeFormat(), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                  const SizedBox(height: 12),
                  Expanded(child: empty
                    ? ExUiErrorOrEmpty(
                        illustration: HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, size: AppStyle.emptyIconSize, color: AppColor.muted).pOnly(bottom: 12),
                        message: 'Cart is empty'.tr,
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _cartItem(context, items[index]),
                      )),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColor.border)),
                  Row(children: [
                    AppIconButton(
                      tooltip: 'Play as Playlist'.tr,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: AppStyle.iconSize),
                      onPressed: empty ? null : () => _playVideos(),
                    ),
                    const SizedBox(width: 8),
                    AppIconButton(
                      tooltip: 'Open in Grid Player'.tr,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.iconSize),
                      onPressed: empty ? null : () => _openInGridPlayer(),
                    ),
                    const SizedBox(width: 8),
                    AppIconButton(
                      tooltip: 'Add to Playlist'.tr,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.iconSize),
                      onPressed: empty ? null : () => HomePanelPlaylist.showDialogAddToPlaylistItem(items),
                    ),
                    const Spacer(),
                    AppIconButton(
                      tooltip: 'Delete All This Files'.tr,
                      color: Theme.of(context).colorScheme.error,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize),
                      onPressed: empty ? null : () => _deleteVideos(items),
                    ),
                  ]),
                ]);
              }),
            ),
          );
        }),
      ),
    );
  }

  static Widget _cartItem(BuildContext context, Videos video) {
    final code = (video.videoCode ?? '').trim();
    final title = (video.title ?? '').trim();
    final path = video.videoPath ?? '';
    final quality = (video.quality ?? '').trim();
    return AppPanel(
      bordered: true,
      padding: const EdgeInsets.all(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExThumbnail(
          imageUrl: video.fanArt ?? '',
          videoPath: video.videoPath,
          width: 80,
          height: 104,
          prefix: 2.2,
          fitUrl: BoxFit.fitWidth,
        ).onDoubleTap(() {
          Overlayment.dismissLast();
          HelperOpener.openVideoFile(video);
        }).cornerRadius(AppStyle.radius).tooltip('Play'.tr),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code.isEmpty ? (title.isEmpty ? 'Untitled'.tr : title) : code,
            maxLines: code.isEmpty ? 3 : 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (code.isNotEmpty && title.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppStyle.fontSize)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (quality.isNotEmpty) _badge(HelperMisc.formatVideoQuality(quality), AppColor.text),
            if (path.isHasUncensored()) _badge('RM', Theme.of(context).colorScheme.error),
            if (path.isHasEnSub()) _badge('EN', AppColor.accentForeground),
            if (path.isHasIdSub()) _badge('ID', AppColor.accentForeground),
          ]),
          const SizedBox(height: 6),
          Text(video.filesize == null || video.filesize! <= 0 ? 'Unknown size'.tr : video.filesize!.toFileSizeFormat(),
            style: TextStyle(fontSize: 11, color: AppColor.muted)).tooltip(path),
        ])),
        const SizedBox(width: 4),
        Column(children: [
          AppIconButton(
            tooltip: 'Remove from Cart'.tr,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRemoveCircle, size: AppStyle.iconSize),
            onPressed: () => _controller.cart.remove(video),
          ),
          MenuAnchor(
            builder: (_, menu, _) => AppIconButton(
              tooltip: 'Video actions'.tr,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, size: AppStyle.iconSize),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
            menuChildren: [MenuItemButton(
              onPressed: () => _deleteVideo(video),
              leadingIcon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: AppStyle.iconSize, color: Theme.of(context).colorScheme.error),
              child: Text('Delete file'.tr, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )],
          ),
        ]),
      ]),
    );
  }

  static Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(AppStyle.radius)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color)),
  );

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
