// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as cmd;
import 'package:uicons_pro/uicons_pro.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../env.g.dart';
import '../core/app_color.dart';
import '../core/app_logging.dart';
import '../core/app_network.dart';
import '../core/const.dart';
import '../data/api/api_javit.dart';
import '../data/database/db_r18.dart';
import '../data/database/db_videos.dart';
import '../data/models/__javit_search_entity.dart';
import '../data/models/videos_entity.dart';
import '../modules/home/home_controller.dart';
import '../modules/home/page_explore/page_explore_controller.dart';
import '../modules/home/page_home/page_home_controller.dart';
import '../modules/home/page_tools/page_tools_controller.dart';
import '../modules/widgets/widget_chiwie_custom.dart';
import '../modules/widgets/widget_thumbnail.dart';
import 'helper.dart';

mixin HelperOpener {
  // open folder
  static Future<void> openFolder(String path) async {
    await cmd.run('open -R "$path"', verbose: false).catchError((e) async {
      await HelperToast.error('File does not exist at path: $path');
    });
  }

  // open file path
  static Future<void> openFilePath(String path) async {
    await cmd.run('open -R "$path"', verbose: false).catchError((e) {
      HelperToast.error('File does not exist at path: $path');
    });
  }

  // open video file -> direct default video player
  static Future<void> openVideoFile(Videos video) async {
    await cmd.run('open "${video.videoPath}"', verbose: false).then((s) async {
      await DBVideos.updateViewCount(video);
      await Get.find<PageHomeController>().getListMostWatch();
    }).catchError((e) async {
      await HelperToast.error('${e.toString()}');
    });
  }

  // ────────────────────────────────────────────────────────────────
  // ** 
  // ────────────────────────────────────────────────────────────────
  static Future<void> openVideoInfo(dynamic item) async {
    late Map<String, dynamic>? dataVideo;
    HelperLoading.show();

    // ** -> from download page
    if (item is JavitSearchResult) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> from library
    else if (item is Videos) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> from r18
    else {
      dataVideo = await DBR18.getVideo(item['video_code']);
    }

    final video = Videos.fromJson(dataVideo ?? {});
    final dataCategory = await DBR18.getCategory(video.videoCode ?? '');
    final dataActress = await DBR18.getActress(video.videoCode ?? '');
    final dataDirector = await DBR18.getDirector(video.videoCode ?? '');

    // prefix
    video.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
    video.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
    video.director = dataDirector?['name_romaji'] ?? '';
    video.releaseDateFormated = video.releaseDate?.reformatDate(from: kYMd, to: kMdY);
    video.durationFormated = HelperMisc.durationFormatDB(video.duration ?? 0);

    HelperLoading.dismiss();

    final _focusNode = FocusNode();

    final _home = Get.find<HomeController>();
    final _explore = Get.find<PageExploreController>();
    final _tool = Get.find<PageToolsController>();

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerRight,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        actions: OverlayActions(
          onReady: () async => _focusNode.requestFocus(),
        ),
        child: FocusScope(
          autofocus: true,
          child: RawKeyboardListener(
            focusNode: _focusNode,
            onKey: (event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  Overlayment.dismissLast();
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  HelperOpener.openScreenshot(video);
                  Overlayment.dismissLast();
                }
              }
            },
            child: VStack(
              [
                ExThumbnail(
                  imageUrl: video.fanArt,
                  videoPath: video.videoPath,
                  width: 300,
                  height: 200,
                  fitMemory: BoxFit.fitHeight,
                  fitUrl: BoxFit.contain,
                ).color(AppColor.selected).onInkTap(() => openScreenshot(video)),
                VStack(
                  [
                    '${video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title.maxWords(3)}'.text.maxLines(2).align(TextAlign.center).bold.makeCentered().onInkTap(() {
                      HelperMisc.copyToClipboard(video.videoCode ?? '', showToast: true);
                    }).pSymmetric(v: 8),
                    '${HelperDecensor.decensor(video.title)}'.text.align(TextAlign.center).size(10).minFontSize(10).maxLines(6).ellipsis.makeCentered().onInkTap(() {
                      HelperMisc.copyToClipboard(video.title ?? '', showToast: true);
                    }).tooltip(video.videoPath?.getFileName().noExt() ?? ''),
                    ExDivider().pSymmetric(v: 16),
                  ],
                ).pSymmetric(h: 16),

                // ** action
                HStack(
                  [
                    Spacer(),

                    // screenshot
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: IconButton(
                        icon: Icon(UIconsPro.regularRounded.comment_image, size: 16),
                        onPressed: () async {
                          await openScreenshot(item);
                        },
                      ),
                    ).pOnly(right: 8).tooltip('Screenshot'),

                    // download
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: IconButton(
                        icon: Icon(UIconsPro.regularRounded.arrow_square_down, size: 16),
                        onPressed: () async {
                          await Overlayment.dismissLast();
                          await launchUrlString('${Env.njavUrl}/en/search/${video.videoCode}');

                          try {
                            item['is_clicked'] = true;
                            _home.update();
                          } catch (_) {}

                          try {
                            item.isClicked = true;
                            _home.update();
                          } catch (_) {}
                        },
                      ),
                    ).pOnly(right: 8).tooltip('Download'),

                    // trailer
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: IconButton(
                        icon: Icon(UIconsPro.regularRounded.video_camera, size: 16),
                        onPressed: () async => await openTrailer(item),
                      ),
                    ).pOnly(right: 8).tooltip('Trailer'),
                    Spacer(),
                  ],
                ).pOnly(bottom: 12),

                // ** metadata
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 100),
                    child: Container(
                      width: double.infinity,
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: SingleChildScrollView(
                        child: VStack([
                          HStack([
                            Icon(UIconsPro.regularRounded.square_code, size: 14).pOnly(right: 8),
                            'Metadata'.text.size(14).bold.make(),
                          ]).pOnly(bottom: 16),

                          // actress
                          if (!video.actress.isEmptyOrNull) ...[
                            'Actress:'.text.size(12).bold.make().pOnly(bottom: 4),
                            Wrap(children: [
                              for (int i = 0; i < video.actress!.length; i++) ...[
                                '${video.actress?[i].nameRomaji == '' ? '${video.actress?[i].nameKana}' : '${video.actress?[i].nameRomaji}'}'
                                    .text
                                    .neutral300
                                    .underline
                                    .size(11)
                                    .minFontSize(11)
                                    .make()
                                    .onInkTap(() async {
                                      // ** on actress clicked
                                      try {
                                        final check = await DBVideos.getByActress(video.actress?[i].nameRomaji ?? '');
                                        final name = '${video.actress?[i].nameRomaji == '' ? '${video.actress?[i].nameKana}' : '${video.actress?[i].nameRomaji}'}';

                                        if (check.isNotEmpty) {
                                          await _home.onMenuChange(kMenuExplore);
                                          await _explore.onMenuChange(kActress);
                                          _explore.tecSearchLeft.text = name;
                                          _explore.onLeftListDoSearch(name);
                                          await _explore.onLeftListTap(_explore.leftListFiltered[0]);
                                        } else {
                                          await _home.onMenuChange(kMenuTools);
                                          await _tool.onMenuChange(kAdvanceSearch);
                                          _tool.currentFilterBy.value = kActress;
                                          _tool.tecFilterSearchLeft.text = name;
                                          await _tool.onLeftListDoSearch(name);
                                          await _tool.onLeftListTap(_tool.leftList[0], 0);
                                        }
                                      } catch (_) {}
                                    })
                                    .tooltip(video.actress?[i].nameRomaji == '' ? '${KanaKit().toRomaji(video.actress?[i].nameKana ?? '')}' : '')
                                    .pOnly(right: 8),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // category
                          if (!video.category.isEmptyOrNull) ...[
                            'Category:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            Wrap(children: [
                              for (int i = 0; i < video.category!.length; i++) ...[
                                '${HelperDecensor.decensor(video.category?[i].category)}'.text.neutral300.underline.size(11).minFontSize(11).make().pOnly(right: 8).onInkTap(() async {
                                  // ** on category clicked
                                  final name = '${HelperDecensor.decensor(video.category?[i].category)}';

                                  try {
                                    await _home.onMenuChange(kMenuExplore);
                                    await _explore.onMenuChange(kCategory);
                                    _explore.tecSearchLeft.text = name;
                                    _explore.onLeftListDoSearch(name);
                                    await _explore.onLeftListTap(_explore.leftListFiltered[0]);
                                  } catch (_) {}
                                }),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // series
                          if (!video.series.isEmptyOrNull) ...[
                            'Series:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${HelperDecensor.decensor(video.series)}'.text.underline.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16).onInkTap(() async {
                              // ** on series clicked
                              try {
                                await Overlayment.dismissLast();
                                final check = await DBVideos.getBySeries(video.series?? '');
                                final name = '${HelperDecensor.decensor(video.series)}';

                                if (check.isNotEmpty) {
                                  await _home.onMenuChange(kMenuExplore);
                                  await _explore.onMenuChange(kSeries);
                                  _explore.tecSearchLeft.text = name;
                                  _explore.onLeftListDoSearch(name);
                                  await _explore.onLeftListTap(_explore.leftListFiltered[0]);
                                } else {
                                  await _home.onMenuChange(kMenuTools);
                                  await _tool.onMenuChange(kAdvanceSearch);
                                  _tool.currentFilterBy.value = kSeries;
                                  _tool.tecFilterSearchLeft.text = name;
                                  await _tool.onLeftListDoSearch(name);
                                  await _tool.onLeftListTap(_tool.leftList[0], 0);
                                }

                              } catch (_) {}
                            })
                          ],

                          // release date
                          if (!video.releaseDate.isEmptyOrNull) ...[
                            'Release Date:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.releaseDateFormated}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // duration
                          if (video.duration != 0) ...[
                            'Duration:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.durationFormated}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // label
                          if (!video.label.isEmptyOrNull) ...[
                            'Label:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.label}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // studio
                          if (!video.studio.isEmptyOrNull) ...[
                            'Studio:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.studio}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // director
                          if (!video.director.isEmptyOrNull) ...[
                            'Director:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.director}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],
                        ]).p12(),
                      ),
                    ).pSymmetric(h: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> openScreenshot(dynamic item) async {
    late Map<String, dynamic>? dataVideo;
    HelperLoading.show();

    // ** -> from download page
    if (item is JavitSearchResult) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> from library
    else if (item is Videos) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> direct from r18
    else {
      dataVideo = await DBR18.getVideo(item['video_code']);
    }

    final video = Videos.fromJson(dataVideo ?? {});

    // Logic for screenshot
    if (dataVideo?['sslast'] != null) {
      final screenshots = <String>[];
      final n = dataVideo?['sslast'].toString().split('-').last;
      for (var i = 0; i < int.parse(n!); i++) {
        final filename = '${dataVideo?['ssfirst']}';
        final part = filename.allBefore('-');
        final suffix = filename.contains('jp-') ? '' : 'jp-';
        screenshots.add('$part$suffix${i + 1}');
      }
      video.screenshot = screenshots;
    }

    HelperLoading.dismiss();

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
                        child: Icon(UIconsPro.regularRounded.arrow_small_right).p12(),
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
                        child: Icon(UIconsPro.regularRounded.arrow_small_left).p12(),
                      ).onInkTap(() {
                        if (idxSelected.value > 0) {
                          idxSelected.value--;
                        }
                      }),
                    ).positioned(left: 8, top: 0, bottom: 0),
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                        child: Icon(UIconsPro.regularRounded.cross_small).p8(),
                      ).onInkTap(() {
                        Overlayment.dismissLast();
                      }),
                    ).positioned(right: 8, top: 8, bottom: 0),
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

  static Future<void> openTrailer(dynamic item) async {
    late Map<String, dynamic>? dataVideo;

    // ** -> from download page
    if (item is JavitSearchResult) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> from library
    else if (item is Videos) {
      final fixCode = item.videoCode?.getVideoCode() ?? '';
      dataVideo = await DBR18.getVideo(fixCode);
    }

    // ** -> direct from r18
    else {
      dataVideo = await DBR18.getVideo(item['video_code']);
    }

    final video = Videos.fromJson(dataVideo ?? {});

    if (video.videoCode.isNullOrEmpty) {
      await HelperToast.warn('Invalid video code');
      return;
    }

    var trailerUrl = '';

    HelperLoading.show();
    if (video.trailer.isNullOrEmpty) {
      await ApiJavit.getMetadata(code: video.videoCode ?? '').then((s) {
        trailerUrl = s.trailer ?? '';
      }).catchError((e) {
        trailerUrl = '';
      });
    } else {
      trailerUrl = video.trailer ?? '';
    }

    late final CachedVideoPlayerPlus cachePlayer;
    trailerUrl = trailerUrl.replaceAll('https://cc3001.dmm.co.jp', 'https://media.javtrailers.com');
    trailerUrl = trailerUrl.replaceAll('https://cc3001.dmm.com', 'https://media.javtrailers.com');

    if (trailerUrl.isNullOrEmpty) {
      HelperLoading.dismiss();
      await HelperToast.warn('Trailer not found');
      return;
    }

    await Api.head('${Env.vidUrl}$trailerUrl').then((s) {
      // ** file mode
      trailerUrl = trailerUrl;
      AppLog.logD('FILE MODE -> $trailerUrl');
      video.site = 'file';
    }).catchError((e) {
      // ** hls mode
      String _prefixVidId(String s) {
        final m = RegExp(r'^(.*?)(\d+)$').firstMatch(s);
        return m == null ? s : '${m[1]}${m[2]!.padLeft(5, '0')}';
      }

      final prefix1 = '${trailerUrl.substring(0, trailerUrl.lastIndexOf('/'))}';
      final prefix2 = '${prefix1.substring(0, prefix1.lastIndexOf('/'))}/${_prefixVidId(video.id!)}/playlist.m3u8'.replaceAll('litevideo', 'hlsvideo');
      final prefix = prefix2;
      trailerUrl = prefix;
      video.site = 'hls';
      AppLog.logD('HLS MODE -> $prefix2');
    });

    // ** DEBUG
    final proxyUrl = Env.vidUrl;
    // trailerUrl = 'https://media.javtrailers.com/hlsvideo/freepv/j/jur/jur00132/playlist.m3u8';
    // trailerUrl = 'https://media.javtrailers.com/litevideo/freepv/1/18s/18sprd1085/18sprd1085_dmb_w.mp4';
    final joinUrl = '${proxyUrl.trim()}${trailerUrl.trim()}';
    // ** END DEBUG

    AppLog.logD('out -> $joinUrl');

    try {
      cachePlayer = CachedVideoPlayerPlus.networkUrl(
        Uri.parse('$joinUrl'),
        invalidateCacheIfOlderThan: 1.seconds,
        skipCache: true,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );

      await cachePlayer.initialize().then((_) async {
        await cachePlayer.controller.play();
        await cachePlayer.controller.setPlaybackSpeed(1.1);
        await cachePlayer.controller.setVolume(0.1);
      });
    } catch (e) {
      e as PlatformException;
      AppLog.logE('open trailer e -> ${e.message}');
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
            cachePlayer.isInitialized ? Chewie(controller: chewie).centered() : const CircularProgressIndicator.adaptive(),
            // '${video.title}'.text.size(11).maxLines(3).ellipsis.minFontSize(11).make().w(Get.width * 70 / 100),
            Align(
              alignment: Alignment.topRight,
              child: Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                child: Icon(UIconsPro.regularRounded.cross_small).p8(),
              ).onInkTap(() {
                Overlayment.dismissLast();
              }),
            ).positioned(right: 8, top: 8, bottom: 0),
          ],
        ),
      ),
    );
  }

  static Future<void> openKeyboardShortcuts() async {
    final shortcuts = <Map<String, String>>[
      {'key': 'Esc', 'action': 'Close Dialog / Panel'},
      {'key': '⌘ + X', 'action': 'Close Dialog / Panel'},
      {'key': '⌘ + R', 'action': 'Reload All Page'},
      {'key': '⌘ + D', 'action': 'Open New Dialog Download'},
      {'key': '⌘ + T', 'action': 'Open New Add Todo'},
      {'key': '⌘ + B', 'action': 'Show/Hide Side Menu'},
      {'key': '⌘ + 1', 'action': 'Open Home Page'},
      {'key': '⌘ + 2', 'action': 'Open Library Page'},
      {'key': '⌘ + 3', 'action': 'Open Explore Page'},
      {'key': '⌘ + 4', 'action': 'Open Download Page'},
      {'key': '⌘ + 5', 'action': 'Open Tool Page'},
      {'key': '⌘ + ,', 'action': 'Open Setting Page'},
    ];
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: MediaQuery.of(Get.context!).size.width * 90 / 100,
        height: MediaQuery.of(Get.context!).size.width * 9.0 / 16.0,
        child: VStack(
          [
            'Keyboard Shortcuts'.text.bold.size(16).make().pOnly(bottom: 12),
            Table(
              border: TableBorder.all(color: AppColor.border),
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(4),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColor.container),
                  children: [
                    'Key'.text.bold.make().p8(),
                    'Action'.text.bold.make().p8(),
                  ],
                ),

                // items
                ...List.generate(
                  shortcuts.length,
                  (index) => TableRow(children: [
                    '${shortcuts[index]['key']}'.text.make().p4(),
                    '${shortcuts[index]['action']}'.text.make().p4(),
                  ]),
                ),
              ],
            ).p12(),
          ],
        ).scrollVertical().p12(),
      ),
    );
  }
}
