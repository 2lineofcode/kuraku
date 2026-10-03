import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_playlist.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/playlist_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_media_stack.dart';
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

  static Future<void> open() async {
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
        actions: OverlayActions(
          onOpen: () async {
            _controller.playlist.value = await DBPlaylist.getAllPlaylist();
            _listFavoriteVideo.value = await DBVideos.getAll(where: 'is_favorite = 1');
          },
          onClose: (p0) async {
            _listVideos.clear();
            _isDetailMode.value = false;
            _isFavoriteMode.value = false;
            _detailFuture = null;
          },
        ),
        child: VStack(
          [
            HStack(
              [
                Icon(UIconsPro.regularRounded.list, size: 16).pOnly(right: 12, left: 8),
                Obx(() => 'Playlist (${_controller.playlist.length})'.text.bold.make()),
                Spacer(),
                Obx(
                  () => IconButton(
                    icon: Icon(Icons.chevron_left_rounded).tooltip('Back'),
                    onPressed: () {
                      _isDetailMode.value = false;
                      _isFavoriteMode.value = false;
                    },
                  ).hide(isVisible: _isDetailMode.isTrue),
                ),
                Obx(
                  () => IconButton(
                    icon: Icon(UIconsPro.regularRounded.plus, size: 13).tooltip('Add New Playlist'),
                    onPressed: () => showDialogAddOrEditPlaylist(),
                  ).hide(isVisible: _isDetailMode.isFalse),
                ),
              ],
            ),
            Divider().pOnly(bottom: 4),
            Obx(() => _isDetailMode.isFalse ? _uiHeader().expand() : _uiDetail().expand()),
            Obx(
              () => _isDetailMode.isTrue
                  ? VStack([
                      Divider(),
                      ExButtonText(
                        label: 'Play This Playlist',
                        width: double.infinity,
                        onPressed: () async {
                          final playableVideos = _listVideos.where((video) {
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
                        },
                      )
                    ])
                  : 0.heightBox,
            ),
          ],
        ).p8(),
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

    ExAlert.adaptive(
      title: Text(playlist == null ? 'New Playlist' : 'Edit Playlist', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack([
        CupertinoTextField(
          controller: tecName,
          focusNode: fnName,
          placeholder: 'Name',
          prefix: Icon(CupertinoIcons.tag, size: 16).pOnly(left: 8),
          style: TextStyle(color: AppColor.text, fontSize: 12),
          readOnly: isFavorite,
        ).disabled(isFavorite).pOnly(bottom: 8),
        CupertinoTextField(
          controller: tecCover,
          placeholder: 'Paste image URL here...',
          prefix: Icon(CupertinoIcons.photo, size: 16).pOnly(left: 8),
          style: TextStyle(fontSize: 12, color: AppColor.text),
        ),
      ]),
      actions: [
        if (playlist != null && !isFavorite) ...[
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              Get.back();
              ExAlert.adaptive(
                title: Text('Are you sure?', style: TextStyle(fontSize: 14)),
                content: Text('Delete this playlist? this action can\'t be undo', style: TextStyle(fontSize: 12)).pOnly(top: 8),
                actions: [
                  CupertinoDialogAction(
                    child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
                    onPressed: () async {
                      Get.back();
                      await DBPlaylist.deletePlaylist(playlist);
                      await _controller.getAllPlaylist();
                    },
                  ),
                  CupertinoDialogAction(
                    child: Text('No', style: TextStyle(fontSize: 13)),
                    onPressed: () => Get.back(),
                  ),
                ],
              );
            },
          ),
        ],
        CupertinoDialogAction(
          child: Text('Submit', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            if (isFavorite) {
              AppPref.setFavoriteCoverURL(tecCover.text);
              Get.back();
              return;
            }

            final name = tecName.text.trim();
            if (name.isEmpty || name.toLowerCase() == 'favorite') {
              await HelperToast.warn(name.isEmpty ? 'Playlist name cannot be empty.' : 'Favorite is reserved for the built-in playlist.');
              return;
            }
            try {
              final edited = Playlist(id: playlist?.id, name: name, cover: tecCover.text);
              final saved = playlist == null ? await DBPlaylist.addPlaylist(edited) : await DBPlaylist.updatePlaylist(edited);
              if (!saved) {
                await HelperToast.warn('Could not save playlist. The name may already be in use or the playlist no longer exists.');
                return;
              }
              Get.back();
              await _controller.getAllPlaylist();
            } catch (e) {
              AppLog.logE('Failed to save playlist: $e');
              await HelperToast.error('Failed to save playlist. Please try again.');
            }
          },
        ),
      ],
    );
  }

  static Future<void> showDialogAddToPlaylistItem(List<Videos> videos) async {
    final allPlaylist = await DBPlaylist.getAllPlaylist();
    if (allPlaylist.isEmpty) {
      await HelperToast.warn('No playlist found. Please create one first.');
      return;
    }

    final playlists = allPlaylist.where((e) => e.id?.isNotEmpty == true).toList();
    if (playlists.isEmpty) {
      await HelperToast.warn('No valid playlist found. Please create one first.');
      return;
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 300,
        height: 300,
        animation: OverFadeAnimation( reverseDurationMilliseconds: 100, durationMilliseconds: 100 ),
        backgroundSettings: BackgroundSettings(blur: 12),
        color: AppColor.panel,

        child: VStack([
          'Select playlist'.text.bold.make().pOnly(bottom: 16),
          ListView.separated(
            itemCount: playlists.length,
            separatorBuilder: (context, index) => 12.heightBox,
            itemBuilder: (context, index) {
              return Container(
                decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                child: HStack([
                  '${playlists[index].name ?? ''}'.text.make(),
                ]).p12(),
              ).onInkTap(() async {
                await Overlayment.dismissLast();
                try {
                  await DBPlaylist.addPlaylistItemBulk(playlists[index].id!, videos);
                  await HelperToast.success('Added ${videos.length} video(s) to ${playlists[index].name}');
                } catch (e) {
                  AppLog.logE('Failed to add playlist items: $e');
                  await HelperToast.error('Failed to add videos. Please reopen the playlist and try again.');
                }
              });
            },
          ).expand(),
        ]).p12(),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ _private
  // ────────────────────────────────────────────────────────────────
  static Widget _uiHeader() {
    return ListView.separated(
      itemCount: _controller.playlist.length + 1,
      separatorBuilder: (context, index) => 12.heightBox,
      itemBuilder: (context, index) {
        
        // * favorite
        if (index == 0) {
          return Container(
            width: 300,
            height: 150,
            color: AppColor.selected,
            child: MediaStack([
              ExThumbnail(
                imageUrl: AppPref.getFavoriteCoverURL(),
                width: 300,
                height: 150,
                fitUrl: BoxFit.cover,
                withProxy: false ,
              ),
              Obx(() => 'Favorite (${_listFavoriteVideo.length})'.text.ellipsis.bold.size(12).make().pSymmetric(h: 8, v: 4).color(AppColor.black180).cornerRadius(90).positioned(bottom: 8, right: 8)),
              Icon(UIconsPro.regularRounded.pen_clip, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
                showDialogAddOrEditPlaylist(
                  playlist: Playlist(
                    name: 'Favorite',
                    cover: AppPref.getFavoriteCoverURL(),
                  ),
                );
              }).positioned(left: 8, top: 4),

            ]).onInkTap(() {
              if (_listFavoriteVideo.isEmpty) return;
              _isFavoriteMode.value = true;
              _playlistSelected.value = Playlist(name: 'Favorite');
              _listVideos.assignAll(_listFavoriteVideo);
              _detailFuture = _buildFavoriteFuture();
              _isDetailMode.value = true;
            }),
          ).cornerRadius(8);
        }

        final item = _controller.playlist[index - 1];
        return Container(
          width: 300,
          height: 150,
          color: AppColor.selected,
          child: MediaStack([
            ExThumbnail(
              imageUrl: item.cover,
              width: 300,
              height: 150,
              fitUrl: BoxFit.cover,
              withProxy: false,
            ),
            '${item.name} (${item.total})'.text.ellipsis.bold.size(12).make().pSymmetric(h: 8, v: 4).color(AppColor.black180).cornerRadius(90).positioned(bottom: 8, right: 8),
            Icon(UIconsPro.regularRounded.pen_clip, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() => showDialogAddOrEditPlaylist(playlist: item)).positioned(left: 8, top: 4),
          ]),
        ).onInkTap(() {
          _isFavoriteMode.value = false;
          _playlistSelected.value = item;
          _detailFuture = null;
          _refreshDetail();
          _isDetailMode.value = true;
        }).cornerRadius(8);
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

        final items = asyncSnapshot.data ?? [];

        if (items.isEmpty) {
          return VStack([
            Icon(UIconsPro.regularRounded.list, size: 28, color: AppColor.muted).pOnly(bottom: 12).centered(),
            'Playlist still empty'.text.size(13).color(AppColor.muted).makeCentered(),
          ]).centered();
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(color: AppColor.border),
          itemBuilder: (context, index) {
            final video = items[index];
            final videoId = video.id;

            if (videoId.isNullOrEmpty) {
              return ListTile(
                leading: Icon(UIconsPro.regularRounded.info_guide, size: 16, color: Vx.orange300),
                title: 'Video not found'.text.size(12).make(),
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
                      await Overlayment.dismissLast();
                      await HelperOpener.openVideoFile(video, playlist: _listVideos);
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
                    if (video.videoPath?.isHasUncensored() == true) ...[
                      'RM'.text.red400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                    ],
                    if (video.videoPath?.isHasEnSub() == true) ...[
                      'EN'.text.blue400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                    ],
                    if (video.videoPath?.isHasIdSub() == true) ...[
                      'ID'.text.blue400.size(11).minFontSize(11).make().pSymmetric(h: 4).color(AppColor.black170).cornerRadius(4).positioned(top: 3, right: 3),
                    ],
                  ]).pOnly(right: 12),
                  VStack([
                    '${video.videoCode == '' ? video.title?.maxWords(5) : video.videoCode}'.text.bold.ellipsis.maxLines(1).minFontSize(13).size(13).make().pOnly(bottom: 12),
                    '${video.title}'.text.minFontSize(12).size(12).maxLines(3).ellipsis.make(),
                    Spacer(),
                    HStack([
                      '${video.filesize?.toFileSizeFormat()}'.text.orange300.size(11).minFontSize(11).make().pOnly(right: 8).tooltip('${video.videoPath}'),
                    ]).pOnly(top: 8),
                  ]).h(110).expand(),
                  VStack(
                    [
                      IconButton(
                        icon: Icon(UIconsPro.regularRounded.minus_circle, size: 14),
                        onPressed: () async {
                          if (_isFavoriteMode.isTrue) {
                            video.isFavorite = 0;
                            await DBVideos.update(video);
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
        );
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
