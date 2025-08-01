// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as cmd;
import 'package:video_player/video_player.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../env.g.dart';
import '../core/app_color.dart';
import '../core/app_logging.dart';
import '../core/app_network.dart';
import '../data/api/api_javit.dart';
import '../data/database/db_r18.dart';
import '../data/database/db_videos.dart';
import '../data/models/__javit_search_entity.dart';
import '../data/models/videos_entity.dart';
import '../modules/home/page_home/page_home_controller.dart';
import '../modules/widgets/widget_chiwie_custom.dart';
import '../modules/widgets/widget_thumbnail.dart';
import 'helper.dart';

mixin HelperOpener {
  static Future<void> openFolder(String path) async {
    await cmd.run('open -R "$path"', verbose: false).catchError((e) async {
      await HelperToast.error('File does not exist at path: $path');
    });
  }

  static Future<void> openVideoFile(Videos video) async {
    await cmd.run('open "${video.videoPath}"', verbose: false).then((s) async {
      await DBVideos.updateViewCount(video);
      await Get.find<PageHomeController>().getListTop10Watch();
    }).catchError((e) async {
      await HelperToast.error('${e.toString()}');
    });
  }

  static Future<void> openFilePath(String path) async {
    await cmd.run('open -R "$path"', verbose: false).catchError((e) {
      HelperToast.error('File does not exist at path: $path');
    });
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ
  // ────────────────────────────────────────────────────────────────
  static Future<void> openTrailer(item) async {
    late Map<String, dynamic>? dataVideo;

    // ** -> from download page
    if (item is JavitSearchResult) {
      final fixCode = HelperMisc.getVideoCode(item.videoCode ?? '');
      dataVideo = await DBR18.getVideo(fixCode);
    }
    // ** -> direct from r18
    else {
      dataVideo = await DBR18.getVideo(item['video_code']);
    }

    final video = Videos.fromJson(dataVideo ?? {});

    if (video.videoCode == null) {
      await HelperToast.warn('Invalid video code');
      return;
    }

    var trailerUrl = '';

    HelperLoading.show();
    if (video.trailer.isNullOrEmpty) {
      AppLog.logD('[1]. trailer is null.. trying to get trailer from javit (${video.videoCode})');

      await ApiJavit.getMetadata(code: video.videoCode ?? '').then((s) {
        trailerUrl = s.trailer ?? '';
        AppLog.logD('[2] trailerUrl from javit -> $trailerUrl');
      });
    } else {
      trailerUrl = video.trailer ?? '';
      AppLog.logD('[2] trailerUrl from db -> $trailerUrl');
    }

    late final CachedVideoPlayerPlus cachePlayer;
    trailerUrl = trailerUrl.replaceAll('https://cc3001.dmm.co.jp', 'https://media.javtrailers.com');
    AppLog.logD('trailerUrl -> $trailerUrl');

    if (trailerUrl.isNullOrEmpty) {
      HelperLoading.dismiss();
      await HelperToast.warn('Trailer not found');
      return;
    }

    await Api.head('${Env.vidUrl}$trailerUrl').then((s) {
      trailerUrl = trailerUrl;
    }).catchError((e) {
      final prefix = '${trailerUrl.substring(0, trailerUrl.lastIndexOf('/') + 1)}playlist.m3u8'.replaceAll('litevideo', 'hlsvideo');
      trailerUrl = prefix;
    });
    AppLog.logD('out -> ${Env.vidUrl}$trailerUrl');

    try {
      cachePlayer = CachedVideoPlayerPlus.networkUrl(
        Uri.parse('${Env.vidUrl}$trailerUrl'),
        invalidateCacheIfOlderThan: 1.seconds,
        skipCache: true,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );

      await cachePlayer.initialize().then((_) async {
        await cachePlayer.controller.play();
        await cachePlayer.controller.setPlaybackSpeed(1.25);
        // await cachePlayer.controller.setVolume(0);
      });
    } catch (e) {
      e as PlatformException;
      AppLog.logE('e -> ${e.message}');
      await HelperToast.warn('${e.message}', duration: 5.seconds);
      HelperLoading.dismiss();
      return;
    }

    final chewie = ChewieController(
      videoPlayerController: cachePlayer.controller,
      autoPlay: true,
      allowFullScreen: false,
      showOptions: false,
      zoomAndPan: true,
      allowMuting: true,
      autoInitialize: true,
      looping: false,
      customControls: ExMaterialControls(video: video),
    );

    await chewie.setVolume(0.1);

    HelperLoading.dismiss();

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: Get.width * 90 / 100,
        height: Get.width * 9.0 / 16.0,
        actions: OverlayActions(
          onClose: (p0) async {
            await cachePlayer.controller.dispose();
            chewie.dispose();
            AppLog.logI('trailer close properly');
          },
        ),
        child: ZStack(
          [
            cachePlayer.isInitialized ? Chewie(controller: chewie).centered().centered() : const CircularProgressIndicator.adaptive(),
            // '${_video?['title']}'.text.size(11).maxLines(3).ellipsis.minFontSize(11).make().positioned(top: 32, left: 12).w(Get.width * 90 / 100),
          ],
        ),
      ),
    );
  }

  static Future<void> openScreenshot(item) async {
    late Map<String, dynamic>? dataVideo;

    // ** -> from download page
    if (item is JavitSearchResult) {
      final fixCode = HelperMisc.getVideoCode(item.videoCode ?? '');
      dataVideo = await DBR18.getVideo(fixCode);
    }
    // ** -> direct from r18
    else {
      dataVideo = await DBR18.getVideo(item['video_code']);
    }

    final video = Videos.fromJson(dataVideo ?? {});

    if (dataVideo?['sslast'] != null) {
      final ss = <String>[];
      final n = dataVideo?['sslast'].toString().split('-').last;
      for (var i = 0; i < int.parse(n!); i++) {
        final filename = '${dataVideo?['ssfirst']}';

        if (!filename.contains('jp-')) {
          final part = filename.allBefore('-');
          final prefix = '${part}jp-${i + 1}';
          ss.add(prefix);
        } else {
          final part = filename.removeLast(1);
          final prefix = '$part${i + 1}';
          ss.add(prefix);
        }
      }
      video.screenshot = ss;
    }

    if (video.screenshot == null || video.screenshot!.isEmpty) {
      await HelperToast.warn('No screenshot found');
      return;
    }

    final idxSelected = 0.obs;
    final focusNode = FocusNode();

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: max(Get.width * 90 / 100, 400),
        height: max(Get.height * 80 / 100, 400),
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        actions: OverlayActions(
          onReady: () async {
            focusNode.requestFocus();
          },
        ),
        child: FocusScope(
          autofocus: true,
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: (event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (idxSelected.value > 0) {
                    idxSelected.value--;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (idxSelected.value < video.screenshot!.length - 1) {
                    idxSelected.value++;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  Overlayment.dismissLast();
                }
              }
            },
            child: VStack(
              [
                ZStack(
                  [
                    Obx(
                      () => Zoom(
                        width: max(Get.width * 90 / 100, 400),
                        height: max(Get.height * 80 / 100, 400) - 80,
                        child: ExThumbnail(
                          imageUrl: '${video.screenshot?[idxSelected.value]}',
                          videoPath: video.videoPath,
                          width: max(Get.width * 90 / 100, 400),
                          height: max(Get.height * 80 / 100, 400) - 80,
                          fitUrl: BoxFit.contain,
                        ),
                      ),
                    ),
                    Obx(
                      () => Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                        child: '${idxSelected.value + 1}/${video.screenshot!.length}'.text.size(11).minFontSize(11).make().p4(),
                      ),
                    ).p12(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                        child: Icon(CupertinoIcons.forward_fill).p12(),
                      ).onInkTap(() {
                        if (idxSelected.value < video.screenshot!.length - 1) {
                          idxSelected.value++;
                        }
                      }),
                    ).positioned(right: 8, top: 0, bottom: 0),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                        child: Icon(CupertinoIcons.backward_fill).p12(), // p12 di dalam Container
                      ).onInkTap(() {
                        if (idxSelected.value > 0) {
                          idxSelected.value--;
                        }
                      }),
                    ).positioned(left: 8, top: 0, bottom: 0),
                  ],
                ),
                Container(height: 5, color: AppColor.container),
                ListView.builder(
                  itemCount: video.screenshot!.length,
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    return ZStack(
                      [
                        ExThumbnail(
                          imageUrl: '${video.screenshot?[index]}',
                          videoPath: video.videoPath,
                          width: 120,
                          height: 70,
                          fitUrl: BoxFit.cover,
                        ).onInkTap(() {
                          idxSelected.value = index;
                        }).pOnly(right: 4),
                        Obx(
                          () => Container(
                            width: 120,
                            height: 70,
                            color: Colors.green.withAlpha(100),
                          ).onInkTap(() => idxSelected.value = index).pOnly(right: 4).hide(isVisible: idxSelected.value == index),
                        ),
                      ],
                    );
                  },
                ).wh(double.infinity, 70),
                Container(height: 5, color: AppColor.container),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
