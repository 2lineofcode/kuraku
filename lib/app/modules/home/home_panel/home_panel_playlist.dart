import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_playlist.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/playlist_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import '../page_home/page_home_controller.dart';

mixin HomePanelPlaylist {
  static final _controller = Get.find<HomeController>();
  static final _playlistSelected = Playlist().obs;
  static final _isDetailMode = false.obs;
  static final _isFavoriteMode = false.obs;
  static final _listVideos = <Videos>[].obs;
  static final _listFavoriteVideo = <Videos>[].obs;
  static Future<List<Videos>>? _detailFuture;
  static bool _isOpen = false;

  static Future<void> refreshVideoContent() async {
    if (!_isOpen) return;
    _listFavoriteVideo.value = await DBVideos.getAll(where: 'is_favorite = 1');
    if (!_isOpen || !_isDetailMode.value) return;
    _detailFuture = _isFavoriteMode.value ? _buildFavoriteFuture() : _buildDetailFuture();
    _isDetailMode.refresh();
    await _detailFuture;
  }

  static Future<void> open() async {
    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 340,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        actions: OverlayActions(
          onOpen: () async {
            _isOpen = true;
            _controller.playlist.value = await DBPlaylist.getAllPlaylist();
            _listFavoriteVideo.value = await DBVideos.getAll(where: 'is_favorite = 1');
          },
          onClose: (p0) async {
            _isOpen = false;
            _listVideos.clear();
            _isDetailMode.value = false;
            _isFavoriteMode.value = false;
            _detailFuture = null;
          },
        ),
        child: VStack(
          [
            Obx(() => Row(children: [
              if (_isDetailMode.isTrue)
                AppIconButton(
                  tooltip: 'Back'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: AppStyle.iconSize),
                  onPressed: () {
                    _isDetailMode.value = false;
                    _isFavoriteMode.value = false;
                  },
                )
              else
                HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.iconSize).pOnly(right: 8),
              Expanded(child: Text(
                _isDetailMode.isTrue
                    ? (_isFavoriteMode.isTrue ? 'Favorite'.tr : _playlistSelected.value.name ?? '')
                    : 'Playlist (@{length})'.trNamed({'length': '${_controller.playlist.length}'}),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              )),
              AppIconButton(
                tooltip: _isDetailMode.isTrue ? 'Edit Playlist'.tr : 'Add New Playlist'.tr,
                icon: HugeIcon(icon: _isDetailMode.isTrue ? HugeIcons.strokeRoundedEdit01 : HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
                onPressed: () => showDialogAddOrEditPlaylist(playlist: _isDetailMode.isTrue
                    ? (_isFavoriteMode.isTrue ? Playlist(name: 'Favorite', cover: AppPref.getFavoriteCoverURL()) : _playlistSelected.value)
                    : null),
              ),
              AppIconButton(
                  tooltip: 'Close'.tr,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize),
                  onPressed: () => Overlayment.dismissLast(),
                ),
            ])),
            Divider().pOnly(bottom: 4),
            Obx(() => _isDetailMode.isFalse ? _uiHeader().expand() : _uiDetail().expand()),
            Obx(
              () => _isDetailMode.isTrue
                  ? VStack([
                      Divider(),
                      AppButton(
                        label: 'Play This Playlist'.tr,
                        variant: AppButtonVariant.outlined,
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: AppStyle.iconSize),
                        width: double.infinity,
                        onPressed: _listVideos.isEmpty ? null : () async {
                          final playableVideos = _listVideos.where((video) {
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
                        },
                      )
                    ])
                  : 0.heightBox,
            ),
          ],
        ).p(AppStyle.panelPadding),
      ),
    );
  }

  static Future<void> showDialogAddOrEditPlaylist({Playlist? playlist}) async {
    if (Overlayment.count > 0) await Overlayment.dismissLast();
    final tecName = TextEditingController();
    final fnName = FocusNode();
    final tecCover = TextEditingController();

    if (playlist != null) {
      tecName.text = playlist.name ?? '';
      tecCover.text = playlist.cover ?? '';
    }

    final isFavorite = playlist != null && playlist.id == null && playlist.name == 'Favorite';
    fnName.requestFocus();

    AppConfirmDialog.show(
      title: Text(playlist == null ? 'New Playlist'.tr : 'Edit Playlist'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack([
        AppTextField(
          controller: tecName,
          focusNode: fnName,
          placeholder: 'Name'.tr,
          prefix: HugeIcon(icon: HugeIcons.strokeRoundedTag01, size: AppStyle.iconSize).pOnly(left: 8),
          style: TextStyle(color: AppColor.text),
          readOnly: isFavorite,
        ).disabled(isFavorite).pOnly(bottom: 8),
        AppTextField(
          controller: tecCover,
          placeholder: 'Paste image URL here...'.tr,
          prefix: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.iconSize).pOnly(left: 8),
          style: TextStyle(color: AppColor.text),
        ),
      ]),
      actions: [
        if (playlist != null && !isFavorite) ...[
          AppDialogAction(
            child: Text('Delete'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              Get.back();
              AppConfirmDialog.show(
                title: Text('Are you sure?'.tr, style: TextStyle(fontSize: 14)),
                content: Text('Delete this playlist? this action can\'t be undo'.tr, style: TextStyle(fontSize: 12)).pOnly(top: 8),
                actions: [
                  AppDialogAction(
                    child: Text('Yes'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
                    onPressed: () async {
                      Get.back();
                      await DBPlaylist.deletePlaylist(playlist);
                      await _controller.getAllPlaylist();
                    },
                  ),
                  AppDialogAction(
                    child: Text('No'.tr, style: TextStyle(fontSize: 13)),
                    onPressed: () => Get.back(),
                  ),
                ],
              );
            },
          ),
        ],
        AppDialogAction(
          child: Text('Submit'.tr, style: TextStyle(fontSize: 13)),
          onPressed: () async {
            if (isFavorite) {
              AppPref.setFavoriteCoverURL(tecCover.text);
              Get.back();
              return;
            }

            final name = tecName.text.trim();
            if (name.isEmpty || name.toLowerCase() == 'favorite') {
              await HelperToast.warn(name.isEmpty ? 'Playlist name cannot be empty.'.tr : 'Favorite is reserved for the built-in playlist.'.tr);
              return;
            }
            try {
              final edited = Playlist(id: playlist?.id, name: name, cover: tecCover.text);
              final saved = playlist == null ? await DBPlaylist.addPlaylist(edited) : await DBPlaylist.updatePlaylist(edited);
              if (!saved) {
                await HelperToast.warn('Could not save playlist. The name may already be in use or the playlist no longer exists.'.tr);
                return;
              }
              Get.back();
              await _controller.getAllPlaylist();
            } catch (e) {
              AppLog.logE('Failed to save playlist: $e');
              await HelperToast.error('Failed to save playlist. Please try again.'.tr);
            }
          },
        ),
      ],
    );
  }

  static Future<void> showDialogAddToPlaylistItem(List<Videos> videos) async {
    final allPlaylist = await DBPlaylist.getAllPlaylist();
    if (allPlaylist.isEmpty) {
      await HelperToast.warn('No playlist found. Please create one first.'.tr);
      return;
    }

    final playlists = allPlaylist.where((e) => e.id?.isNotEmpty == true).toList();
    if (playlists.isEmpty) {
      await HelperToast.warn('No valid playlist found. Please create one first.'.tr);
      return;
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 340,
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        backgroundSettings: BackgroundSettings(blur: 12),
        decoration: BoxDecoration(
          color: AppColor.panel,
          borderRadius: BorderRadius.circular(AppStyle.radius + 2),
          border: Border.all(color: AppColor.border),
        ),
        child: PlaylistSelectionDialog(
          playlists: playlists,
          onClose: () => Overlayment.dismissLast(),
          onSelected: (playlist) async {
            await Overlayment.dismissLast();
            try {
              await DBPlaylist.addPlaylistItemBulk(playlist.id!, videos);
              await HelperToast.success('Added @{length} video(s) to @{name}'.trNamed({'length': '${videos.length}', 'name': '${playlist.name}'}));
            } catch (e) {
              AppLog.logE('Failed to add playlist items: $e');
              await HelperToast.error('Failed to add videos. Please reopen the playlist and try again.'.tr);
            }
          },
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ _private
  // ────────────────────────────────────────────────────────────────
  static Widget _uiHeader() {
    final favorite = Playlist(name: 'Favorite', cover: AppPref.getFavoriteCoverURL(), total: _listFavoriteVideo.length);
    return ListView.separated(
      itemCount: _controller.playlist.length + 1,
      separatorBuilder: (context, index) => 8.heightBox,
      itemBuilder: (context, index) {
        final isFavorite = index == 0;
        final item = isFavorite
            ? favorite
            : _controller.playlist[index - 1];
        final name = isFavorite ? 'Favorite'.tr : item.name ?? '';
        return AppPanel(
          bordered: true,
          padding: EdgeInsets.zero,
          child: Row(children: [
            Expanded(child: AppButton(
              padding: EdgeInsets.all(8),
              onPressed: () {
                _isFavoriteMode.value = isFavorite;
                _playlistSelected.value = item;
                _detailFuture = isFavorite ? _buildFavoriteFuture() : _buildDetailFuture();
                _isDetailMode.value = true;
              },
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppStyle.radius),
                  child: (item.cover ?? '').trim().isEmpty
                      ? Container(width: 64, height: 56, color: AppColor.selected,
                          child: HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.largeIconSize, color: AppColor.muted))
                      : ExThumbnail(imageUrl: item.cover, width: 64, height: 56, fitUrl: BoxFit.cover, withProxy: false),
                ),
                12.widthBox,
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)).tooltip(name),
                  4.heightBox,
                  Text('${item.total} ${'Videos'.tr}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
                ])),
              ]),
            )),
            AppIconButton(
              tooltip: 'Edit Playlist'.tr,
              icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize),
              onPressed: () => showDialogAddOrEditPlaylist(playlist: item),
            ).pOnly(right: 4),
          ]),
        );
      },
    );
  }

  static Widget _uiDetail() {
    _detailFuture ??= _buildDetailFuture();

    return FutureBuilder<List<Videos>>(
      future: _detailFuture,
      builder: (context, asyncSnapshot) {
        if (asyncSnapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CupertinoActivityIndicator(radius: 12),
          );
        }

        if (asyncSnapshot.hasError) {
          return VStack([
            HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.emptyIconSize, color: AppColor.muted).pOnly(bottom: 12),
            'Failed to load playlist.'.tr.text.size(13).color(AppColor.muted).make(),
            AppButton(label: 'Retry'.tr, variant: AppButtonVariant.outlined, onPressed: () {
              _refreshDetail();
              _isDetailMode.refresh();
            }).pOnly(top: 12),
          ]).centered();
        }

        final items = asyncSnapshot.data ?? [];

        if (items.isEmpty) {
          return VStack([
            HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.emptyIconSize, color: AppColor.muted).pOnly(bottom: 12).centered(),
            'Playlist still empty'.tr.text.size(13).color(AppColor.muted).makeCentered(),
          ]).centered();
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${items.length} ${'Videos'.tr}', style: TextStyle(fontSize: 11, color: AppColor.muted)).pOnly(bottom: 8),
          Expanded(child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(color: AppColor.border),
          itemBuilder: (context, index) {
            final video = items[index];
            final videoId = video.id;

            if (videoId.isNullOrEmpty) {
              return ListTile(
                leading: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.iconSize, color: Vx.orange300),
                title: 'Video not found'.tr.text.size(12).make(),
              );
            }

            return Container(
              child: HStack(
                alignment: MainAxisAlignment.start,
                crossAlignment: CrossAxisAlignment.start,
                [
                  ZStack([
                    ExThumbnail(
                      imageUrl: '${video.fanArt ?? ''}',
                      videoPath: video.videoPath,
                      width: 90,
                      height: 110,
                      prefix: 2.2,
                      fitUrl: BoxFit.fitWidth,
                    ).onDoubleTap(() async {
                      final playlist = _listVideos.toList();
                      await Overlayment.dismissLast();
                      await HelperOpener.openVideoFile(video, playlist: playlist);
                    }).cornerRadius(4),
                    '${HelperMisc.formatVideoQuality(video.quality ?? '').maxWords(1)}'
                        .text
                        .orange300
                        .size(11)
                        .minFontSize(11)
                        .make()
                        .pSymmetric(h: 4)
                        .color(AppColor.black170)
                        .cornerRadius(4)
                        .positioned(bottom: 3, left: 3),
                    Positioned(top: 3, right: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (video.videoPath?.isHasUncensored() == true)
                        'RM'.text.red400.size(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4),
                      if (video.videoPath?.isHasEnSub() == true)
                        'EN'.text.blue400.size(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4),
                      if (video.videoPath?.isHasIdSub() == true)
                        'ID'.text.blue400.size(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4),
                    ])),
                  ]).pOnly(right: 12),
                  VStack([
                    '${(video.videoCode ?? '').isEmpty ? video.title?.maxWords(5) ?? '' : video.videoCode}'.text.bold.ellipsis.maxLines(1).minFontSize(13).size(13).make().pOnly(bottom: 12),
                    (video.title ?? '').text.minFontSize(12).size(12).maxLines(3).ellipsis.make(),
                    Spacer(),
                    HStack([
                      '${video.filesize?.toFileSizeFormat() ?? ''}'.text.orange300.size(11).minFontSize(11).make().pOnly(right: 8).tooltip('${video.videoPath}'),
                    ]).pOnly(top: 8),
                  ]).h(110).expand(),
                  VStack(
                    [
                      AppIconButton(
                        tooltip: _isFavoriteMode.isTrue ? 'Remove from favorites'.tr : 'Remove from playlist'.tr,
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedRemoveCircle, size: AppStyle.iconSize),
                        onPressed: () async {
                          if (_isFavoriteMode.isTrue) {
                            await DBVideos.removeFromFavorite(video);
                            _listFavoriteVideo.removeWhere((v) => v.id == video.id);
                            _listVideos.removeWhere((v) => v.id == video.id);
                            _detailFuture = _buildFavoriteFuture();
                            await Get.find<PageHomeController>().getListFavorite();
                            _controller.update();
                          } else {
                            await DBPlaylist.deletePlaylistItems(_playlistSelected.value.id ?? '', videoId!);
                            _controller.playlist.value = await DBPlaylist.getAllPlaylist();
                            _refreshDetail();
                          }
                          _isDetailMode.refresh(); // force FutureBuilder rebuild
                        },
                      ),
                    ],
                  ),
                ],
              ).p8(),
            );
          },
          )),
        ]);
      },
    );
  }

  static Future<List<Videos>> _buildDetailFuture() async {
    if (_isFavoriteMode.isTrue) return _buildFavoriteFuture();

    _listVideos.clear();
    final videos = await DBPlaylist.getPlaylist(_playlistSelected.value.id ?? '');
    _listVideos.assignAll(videos);
    return videos;
  }

  static Future<List<Videos>> _buildFavoriteFuture() async {
    final videos = _listFavoriteVideo.toList();
    _listVideos.assignAll(videos);
    return videos;
  }

  static void _refreshDetail() {
    _detailFuture = _buildDetailFuture();
  }

}

class PlaylistSelectionDialog extends StatelessWidget {
  const PlaylistSelectionDialog({super.key, required this.playlists, required this.onSelected, required this.onClose});

  final List<Playlist> playlists;
  final ValueChanged<Playlist> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(autofocus: true, child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Padding(
          padding: const EdgeInsets.all(AppStyle.panelPadding),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.iconSize),
              const SizedBox(width: 8),
              Expanded(child: Text('Select playlist'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close, size: AppStyle.iconSize), onPressed: onClose),
            ]),
            Divider(height: 16, color: AppColor.border),
            Flexible(child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: playlists.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final name = playlist.name ?? '';
                return AppButton(
                  variant: AppButtonVariant.outlined,
                  backgroundColor: AppColor.container,
                  padding: const EdgeInsets.all(12),
                  onPressed: () => onSelected(playlist),
                  child: Row(children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.largeIconSize, color: AppColor.muted),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)).tooltip(name),
                      const SizedBox(height: 4),
                      Text('${playlist.total} ${'Videos'.tr}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
                    ])),
                    const SizedBox(width: 8),
                    HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: AppStyle.iconSize, color: AppColor.muted),
                  ]),
                );
              },
            )),
          ]),
        ),
      )),
    );
  }
}
