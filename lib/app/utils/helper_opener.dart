import 'dart:math';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as cmd;
import 'package:translator/translator.dart';
import 'package:uicons_pro/uicons_pro.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../env.g.dart';
import '../core/app_color.dart';
import '../core/app_logging.dart';
import '../core/app_network.dart';
import '../core/app_pref.dart';
import '../core/const.dart';
import '../data/api/api_javit.dart';
import '../data/database/db_r18.dart';
import '../data/database/db_videos.dart';
import '../data/models/__javit_search_entity.dart';
import '../data/models/videos_entity.dart';
import '../modules/home/home_controller.dart';
import '../modules/home/home_panel/home_panel_video_info.dart';
import '../modules/home/page_explore/page_explore_controller.dart';
import '../modules/home/page_home/page_home_controller.dart';
import '../modules/home/page_tools/page_tools_controller.dart';
import '../modules/player/player_controller.dart';
import '../modules/widgets/widget_auto_complate.dart';
import '../modules/widgets/widget_chiwie_custom.dart';
import '../modules/widgets/widget_thumbnail.dart';
import '../routes/app_pages.dart';
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
  static Future<void> openVideoFile(Videos video, {List<Videos>? playlist}) async {
    final _defaultPlayer = AppPref.getDefaultPlayer();

    if (_defaultPlayer == 'In App') {
      final controller = Get.isRegistered<PlayerController>()
          ? Get.find<PlayerController>()
          : Get.put<PlayerController>(PlayerController(), permanent: true);

      final started = await controller.startPlayback(video, playlist: playlist);
      if (!started) return;

      controller.exitMiniMode();
      if (Get.currentRoute != Routes.PLAYER) {
        await Get.toNamed(Routes.PLAYER);
      } else {
        controller.requestFocusOnPlayer();
      }
    } else {
      await cmd.run('open "${video.videoPath}"', verbose: false).then((s) async {
        await DBVideos.updateViewCount(video);
        await Get.find<PageHomeController>().getListMostWatch();
      }).catchError((e) async {
        await HelperToast.error('${e.toString()}');
      });
    }
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

    // new
    try {
      final x = await DBVideos.getByCode(video.videoCode ?? '');
      if (x.videoCode.isNotEmptyAndNotNull) {
        HelperLoading.dismiss();
        await HomePanelVideoInfo.open(x);
        return;
      }
    } catch (_) {}

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

    final _translatedTitle = HelperDecensor.decensor(video.title ?? '').obs;

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
        actions: OverlayActions(onReady: () async => _focusNode.requestFocus()),
        child: FocusScope(
          autofocus: true,
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
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
                    Obx(
                      () => _translatedTitle.value.text.align(TextAlign.center).size(10).minFontSize(10).makeCentered().onInkTap(
                        () async {
                          HelperMisc.copyToClipboard(video.title, showToast: true);
                          final translator = GoogleTranslator();
                          final result = await translator.translate(video.title ?? '', from: 'en', to: 'id');
                          final translated = '${result.text}'.trim();
                          _translatedTitle.value = HelperDecensor.decensor(translated);
                          video.title = translated;
                        },
                      ),
                    ).tooltip(video.videoPath ?? ''),
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

                          final searchEngine = AppPref.getDefaultSearchEngine();
                          switch (searchEngine.toLowerCase()) {
                            case 'njav':
                              await launchUrlString('${Env.njavUrl}/${video.videoCode}');
                              break;
                            case 'missav':
                              await launchUrlString('${Env.missavUrl}/${video.videoCode}');
                              break;
                            case 'javmost':
                              await launchUrlString('${Env.javmostUrl}/${video.videoCode}');
                              break;
                            case 'sextb':
                              await launchUrlString('${Env.sextbUrl}/${video.videoCode}');
                              break;
                            case 'javguru':
                              await launchUrlString('${Env.javguruUrl}/?s=${video.videoCode}');
                              break;
                            default:
                              await launchUrlString('${Env.njavUrl}/${video.videoCode}');
                              break;
                          }

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
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1, fillColor: Colors.transparent),
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
                                final check = await DBVideos.getBySeries(video.series ?? '');
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
      final total = int.parse(dataVideo!['sslast'].toString().split('-').last);
      final filename = dataVideo['ssfirst'].toString();
      final base = filename.contains('jp-') ? filename.removeLast(1) : '${filename.allBefore('-')}jp-';

      for (var i = 1; i <= total; i++) {
        screenshots.add('$base$i');
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

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: max(Get.width * 90 / 100, 400),
        height: max(Get.height * 80 / 100, 400),
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
        actions: OverlayActions(onReady: () async => focusNode.requestFocus()),
        child: FocusScope(
          autofocus: true,
          child: KeyboardListener(
            focusNode: focusNode,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
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
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                        child: '${idxSelected.value + 1}/${video.screenshot!.length}'.text.size(11).minFontSize(11).make().p4(),
                      ),
                    ).p12(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
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
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
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
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
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

    // AppLog.logD('video -> $video');
    // return;

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

    await Api.head('${trailerUrl.genTrailerUrl()}').then((s) {
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

    final joinUrl = '${trailerUrl.trim().genTrailerUrl()}';

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
      customControls: ExChewieCustom(video: video),
    );

    HelperLoading.dismiss();

    WidgetsBinding.instance.scheduleFrame();
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
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
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
      {'key': 'Esc',    'action': 'Close dialog/panel'},

      {'key': '⌘ + 1',  'action': 'Go to Home'},
      {'key': '⌘ + 2',  'action': 'Go to Library'},
      {'key': '⌘ + 3',  'action': 'Go to Explore'},
      {'key': '⌘ + 4',  'action': 'Go to Downloads'},
      {'key': '⌘ + 5',  'action': 'Go to Tools'},
      {'key': '⌘ + B',  'action': 'Show/hide side menu (mini mode)'},
      {'key': '⌘ + D',  'action': 'Open new download dialog'},
      {'key': '⌘ + E',  'action': 'Open video cart panel'},
      {'key': '⌘ + L',  'action': 'Open app log panel'},
      {'key': '⌘ + P',  'action': 'Open playlist panel'},
      {'key': '⌘ + R',  'action': 'Reload all pages'},
      {'key': '⌘ + T',  'action': 'Add new todo'},

      {'key': '⌘ + ,',  'action': 'Open Settings'},
      {'key': '⌘ + .',  'action': 'Open relapse panel'},
    ];

    
    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerLeft,
        width: 400,
        height: Get.height,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerLeft, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black,
        child: VStack(
          [
            HStack(
              [
                'Keyboard Shortcuts'.text.bold.size(16).make().pOnly(left: 12),
                Spacer(),
                IconButton(
                  icon: Icon(UIconsPro.regularRounded.cross, size: 14),
                  onPressed: () => Overlayment.dismissLast(),
                ),
              ],
            ).pOnly(bottom: 4),
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

  // ────────────────────────────────────────────────────────────────
  // ⵌ filter
  // ────────────────────────────────────────────────────────────────
  static Future<void> openFilterDialog<T>({
    required VideoFilterState state,
    required List<T> allVideos,
    required RxList<T> videos,
    required VideoFilterAdapter<T> adapter,
    Future<void> Function()? onReset,
    Future<void> Function(List<T> filtered)? onApplied,
    double widthFactor = 0.5,
    bool? showVideoCode = true,
    bool? showActressName = true,
    bool? showCategories = true,
    bool? showYears = true,
    bool applyLocalFilter = true,
  }) async {
    await state.ensureOptionsLoaded();
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    if (Get.context == null) return;
    final visibleSectionCount = [
      showVideoCode ?? true,
      showActressName ?? true,
      showCategories ?? true,
      showYears ?? true,
    ].where((v) => v).length;
    final panelHeight = 180 + (visibleSectionCount * 45);

    await Overlayment.show(
      context: Get.context!,
      OverPanel(
        alignment: Alignment.center,
        width: 500,
        height: panelHeight.toDouble().clamp(220, 340),
        backgroundSettings: BackgroundSettings(blur: 5, color: Colors.transparent),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
        child: VStack(
          [
            'Filter'.text.bold.make().pOnly(bottom: 16),
            Container(
              decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 12, fillColor: Colors.black),
              child: VStack(
                [
                  HStack(
                    [
                      if (showVideoCode ?? true) ...[
                        CupertinoTextField(
                          controller: state.tecVideoCode,
                          clearButtonMode: OverlayVisibilityMode.editing,
                          placeholder: 'Video Code..',
                          style: TextStyle(color: Vx.white, fontSize: 12),
                        ).expand(),
                        12.widthBox,
                      ],
                      if (showActressName ?? true) ...[
                        ExAutoComplate(
                          controller: state.tecActressName,
                          items: state.actresses,
                          fontSize: 12,
                          placeHolder: 'Actress Name (${state.actresses.length})',
                          onSelected: (s) => state.tecActressName.text = s,
                        ).expand(),
                      ],
                    ],
                  ).pOnly(bottom: 16),
                  if (showCategories ?? true) ...[
                    Obx(
                      () => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.categoriesSelected.map((tag) {
                          return Chip(
                            label: Text(tag, style: TextStyle(fontSize: 9)),
                            deleteIcon: Icon(Icons.close, size: 12),
                            labelPadding: EdgeInsets.all(2),
                            side: BorderSide(color: AppColor.container),
                            backgroundColor: AppColor.selected,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1)),
                            onDeleted: () => {
                              state.categoriesSelected.remove(tag),
                            },
                          );
                        }).toList(),
                      ).pOnly(bottom: 12),
                    ),
                    ExAutoComplate(
                      controller: state.tecCategory,
                      items: state.categories,
                      fontSize: 12,
                      placeHolder: 'Add Category (${state.categories.length})',
                      emptyText: 'No Category with `${state.tecCategory.text}` Found ',
                      onSelected: (s) {
                        state.tecCategory.clear();
                        if (state.categoriesSelected.contains(s)) return;
                        state.categoriesSelected.add(s);
                      },
                    ).pOnly(bottom: 12),
                  ],
                  if (showYears ?? true) ...[
                    HStack(
                      [
                        'Year:'.text.size(11).make().pOnly(right: 24),
                        Obx(
                          () => SliderTheme(
                            data: SliderTheme.of(Get.context!).copyWith(
                              trackHeight: 4,
                              overlayShape: SliderComponentShape.noOverlay,
                              activeTrackColor: AppColor.selected,
                              inactiveTrackColor: AppColor.container,
                              rangeTrackShape: RectangularRangeSliderTrackShape(),
                              valueIndicatorTextStyle: const TextStyle(fontSize: 10, color: Colors.white),
                              valueIndicatorColor: AppColor.container,
                              rangeThumbShape: RoundRangeSliderThumbShape(
                                enabledThumbRadius: 6,
                                disabledThumbRadius: 0,
                              ),
                            ),
                            child: RangeSlider(
                              values: state.currentRange.value,
                              min: 2000,
                              max: DateTime.now().year.toDouble(),
                              divisions: (DateTime.now().year.toDouble() - 2000).toInt(),
                              labels: RangeLabels(
                                state.currentRange.value.start.toInt().toString(),
                                state.currentRange.value.end.toInt().toString(),
                              ),
                              onChanged: (RangeValues values) {
                                state.currentRange.value = values;
                              },
                            ),
                          ).expand(),
                        ),
                        Obx(() => '${state.currentRange.value.start.toInt()} - ${state.currentRange.value.end.toInt()}'.text.size(11).make().pOnly(left: 24)),
                      ],
                    ),
                  ],
                ],
              ).p12(),
            ),
            HStack(
              [
                Spacer(),
                ExButtonElevated(
                  height: 38,
                  label: 'Reset',
                  backgroundColor: Vx.red500.withAlpha(100),
                  labelColor: Vx.white,
                  labelSize: 12,
                  onPressed: () async {
                    state.reset();
                    if (applyLocalFilter) {
                      videos.value = allVideos;
                    }
                    if (onReset != null) await onReset();
                    await Overlayment.dismissLast();
                  },
                ).pOnly(right: 8),
                ExButtonElevated(
                  height: 38,
                  label: 'Apply',
                  labelSize: 12,
                  backgroundColor: AppColor.selected,
                  labelColor: Vx.white,
                  onPressed: () async {
                    if (applyLocalFilter) {
                      final filtered = state.apply(allVideos, adapter);
                      videos.value = filtered;
                      if (onApplied != null) await onApplied(filtered);
                    } else {
                      state.isFiltered.value = true;
                      if (onApplied != null) await onApplied(const []);
                    }
                    await Overlayment.dismissLast();
                  },
                ),
              ],
            ).pOnly(top: 24, bottom: 16),
          ],
        ).p16(),
      ),
    );
  }
}

class VideoFilterAdapter<T> {
  const VideoFilterAdapter({
    required this.videoCode,
    required this.actresses,
    required this.categories,
    required this.releaseDate,
    this.categoryMatch,
  });

  final String Function(T video) videoCode;
  final Iterable<String> Function(T video) actresses;
  final Iterable<String> Function(T video) categories;
  final String? Function(T video) releaseDate;
  final bool Function(Iterable<String> videoCategories, Set<String> selected)? categoryMatch;
}

class VideoFilterState {
  VideoFilterState({RxBool? isFiltered}) : isFiltered = isFiltered ?? false.obs;

  final RxBool isFiltered;
  final tecVideoCode = TextEditingController();
  final tecActressName = TextEditingController();
  final tecCategory = TextEditingController();
  final actresses = <String>[].obs;
  final categories = <String>[].obs;
  final categoriesSelected = <String>[].obs;
  final currentRange = RangeValues(2000, DateTime.now().year.toDouble()).obs;

  Future<void> ensureOptionsLoaded() async {
    if (actresses.isEmpty) {
      await DBR18.getAllActress().then((actress) {
        for (var i = 0; i < actress.length; i++) {
          actresses.add('${actress[i]['name_romaji']}');
        }
        actresses.unique();
      });
    }

    if (categories.isEmpty) {
      await DBR18.getAllCategories().then((cat) {
        for (var i = 0; i < cat.length; i++) {
          categories.add('${cat[i]['name_en']}');
        }
        categories.unique();
      });
    }
  }

  void reset() {
    tecVideoCode.text = '';
    tecActressName.text = '';
    tecCategory.text = '';
    actresses.clear();
    categories.clear();
    categoriesSelected.clear();
    currentRange.value = RangeValues(2000, DateTime.now().year.toDouble());
    isFiltered.value = false;
  }

  List<T> apply<T>(List<T> allVideos, VideoFilterAdapter<T> adapter) {
    var filteredVideos = allVideos.toList();

    if (tecVideoCode.text.isNotBlank) {
      final query = tecVideoCode.text.toLowerCase();
      filteredVideos = filteredVideos.where((video) => adapter.videoCode(video).toLowerCase().contains(query)).toList();
    }

    if (tecActressName.text.isNotBlank) {
      final query = tecActressName.text.toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        return adapter.actresses(video).any((name) => name.toLowerCase().contains(query));
      }).toList();
    }

    if (categoriesSelected.isNotEmpty) {
      final selected = categoriesSelected.toSet();
      if (adapter.categoryMatch != null) {
        filteredVideos = filteredVideos.where((video) {
          return adapter.categoryMatch!(adapter.categories(video), selected);
        }).toList();
      } else {
        filteredVideos = filteredVideos.where((video) {
          return adapter.categories(video).any((category) => category.isNotEmpty && selected.contains(category));
        }).toList();
      }
    }

    if (currentRange.value.start.toInt() > 0 || currentRange.value.end.toInt() > 0) {
      filteredVideos = filteredVideos.where((video) {
        final releaseDate = adapter.releaseDate(video);
        if (releaseDate.isEmptyOrNull) return false;
        final DateTime date;
        try {
          date = releaseDate!.toDateEx(format: kYMd);
        } catch (_) {
          return false;
        }
        final year = date.year;
        final startYear = currentRange.value.start.toInt();
        final endYear = currentRange.value.end.toInt();
        return year >= startYear && year <= endYear;
      }).toList();
    }

    isFiltered.value = true;
    return filteredVideos;
  }
}
