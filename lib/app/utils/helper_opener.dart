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
// import 'package:process_run/process_run.dart' as shell;
import 'package:uicons_pro/uicons_pro.dart';
// import 'package:url_launcher/url_launcher_string.dart';
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
import '../modules/home/page_download/page_download_controller.dart';
import '../modules/home/page_explore/page_explore_controller.dart';
import '../modules/home/page_home/page_home_controller.dart';
import '../modules/home/page_tools/page_tools_controller.dart';
import '../modules/player/player_controller.dart';
import '../modules/widgets/widget_auto_complate.dart';
import '../modules/widgets/widget_chiwie_custom.dart';
import '../modules/widgets/widget_media_stack.dart';
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
    Map<String, dynamic>? dataVideo;
    HelperLoading.show();

    final candidates = <String>[];


    void _pushCode(String? value) {
      final code = (value ?? '').trim();
      if (code.isEmpty) return;
      if (candidates.contains(code)) return;
      candidates.add(code);
    }

    String _getRawCode(dynamic source) {
      if (source is JavitSearchResult) return source.videoCode ?? '';
      if (source is Videos) return HelperMisc.resolveVideoCode(videoCode: source.videoCode, videoPath: source.videoPath, title: source.title);
      if (source is Map<String, dynamic>) return source['video_code']?.toString() ?? '';
      return '';
    }

    final rawCode = _getRawCode(item);
    _pushCode(rawCode);
    _pushCode(rawCode.getVideoCode());
    _pushCode(rawCode.toUpperCase());
    _pushCode(rawCode.getVideoCode().toUpperCase());

    for (final code in candidates) {
      dataVideo = await DBR18.getVideo(code);
      if (dataVideo != null) break;
    }

    // ** -> from download page
    if (dataVideo == null && item is JavitSearchResult) {
      dataVideo = {
        'video_code': item.videoCode ?? rawCode,
        'title': item.title ?? '',
        'fan_art': item.fanArt ?? '',
        'poster': item.poster ?? '',
        'trailer': item.trailer ?? '',
        'release_date': item.releaseDate ?? '',
        'duration': item.duration ?? 0,
      };
    }

    final video = Videos.fromJson(dataVideo ?? {});
    final resolvedCode = (video.videoCode ?? '').trim();
    final dataCategory = resolvedCode.isEmpty ? <Map<String, dynamic>>[] : await DBR18.getCategory(resolvedCode);
    final dataActress = resolvedCode.isEmpty ? <Map<String, dynamic>>[] : await DBR18.getActress(resolvedCode);
    final dataDirector = resolvedCode.isEmpty ? null : await DBR18.getDirector(resolvedCode);

    // new
    try {
      if (resolvedCode.isEmpty) throw Exception('empty video code');
      final x = await DBVideos.getByCode(resolvedCode);
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
        color: AppColor.panel,
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
                      HelperMisc.copyToClipboard(video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title, showToast: true);
                    }).pSymmetric(v: 8),
                    Obx(
                      () => _translatedTitle.value.text.align(TextAlign.center).size(10).minFontSize(10).makeCentered().onInkTap(
                        () async {
                          HelperMisc.copyToClipboard(video.title, showToast: true);
                          // final translator = GoogleTranslator();
                          // final result = await translator.translate(video.title ?? '', from: 'en', to: 'id');
                          // final translated = '${result.text}'.trim();
                          // _translatedTitle.value = HelperDecensor.decensor(translated);
                          // video.title = translated;
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
                          late String url;
                          switch (searchEngine.toLowerCase()) {
                            case 'njav':
                              // await launchUrlString('${Env.njavUrl}/${video.videoCode}');
                              url = '${Env.njavUrl}/en/${video.videoCode}'.replaceAll('/en/search', '');
                              url += '-uncensored-leak';
                              // await shell.run('open downie://XUOpenURL?url=$url');
                              break;
                            case 'missav':
                              // await launchUrlString('${Env.missavUrl}/${video.videoCode}');
                              url = '${Env.missavUrl}/en/${video.videoCode}'.replaceAll('/en/search', '');
                              url += '-uncensored-leak';
                              // await shell.run('open downie://XUOpenURL?url=$url');
                              break;
                            case 'javmost':
                              url = '${Env.javmostUrl}/${video.videoCode}'.replaceAll('/search', '');
                              // await shell.run('open downie://XUOpenURL?url=$url');
                              break;
                            case 'sextb':
                              url = '${Env.sextbUrl}/${video.videoCode}'.replaceAll('/search', '');
                              // await shell.run('open downie://XUOpenURL?url=$url');
                              break;
                            case 'javguru':
                              url = '${Env.javguruUrl}/?s=${video.videoCode}';
                              // await shell.run('open downie://XUOpenURL?url=$url');
                              break;
                            default:
                              url = '${Env.njavUrl}/${video.videoCode}';
                              // await launchUrlString(url);
                              break;
                          }

                          Get.find<PageDownloadController>().downloadWebsite(url);

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
                                    .color(AppColor.muted)
                                    .underline
                                    .size(11)
                                    .minFontSize(11)
                                    .make()
                                    .onInkTap(() async {
                                      // ** on actress clicked
                                      final newTab = PageExploreController.isNewTabModifierPressed;
                                      try {
                                        final name = '${video.actress?[i].nameRomaji == '' ? '${video.actress?[i].nameKana}' : '${video.actress?[i].nameRomaji}'}';
                                        final isRomaji = RegExp(r"^[A-Za-z0-9 .,'-]+$").hasMatch(name) && RegExp(r'[A-Za-z]').hasMatch(name);

                                        if (isRomaji == false) {
                                          await _home.onMenuChange(kMenuTools);
                                          await _tool.onMenuChange(kAdvanceSearch);
                                          _tool.currentFilterBy.value = kActress;
                                          _tool.tecFilterSearchLeft.text = name;
                                          await _tool.onLeftListDoSearch(name);
                                          await _tool.onLeftListTap(_tool.leftList[0], 0);
                                        } else {
                                          final check = await DBVideos.getByActress(video.actress?[i].nameRomaji ?? '');
                                          if (check.isNotEmpty) {
                                            await _home.onMenuChange(kMenuExplore);
                                            await _explore.openSelection(kActress, name, newTab: newTab);
                                          } else {
                                            await _home.onMenuChange(kMenuTools);
                                            await _tool.onMenuChange(kAdvanceSearch);
                                            _tool.currentFilterBy.value = kActress;
                                            _tool.tecFilterSearchLeft.text = name;
                                            await _tool.onLeftListDoSearch(name);
                                            await _tool.onLeftListTap(_tool.leftList[0], 0);
                                          }
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
                                '${HelperDecensor.decensor(video.category?[i].category)}'.text.color(AppColor.muted).underline.size(11).minFontSize(11).make().pOnly(right: 8).onInkTap(() async {
                                  // ** on category clicked
                                  final newTab = PageExploreController.isNewTabModifierPressed;
                                  final name = '${HelperDecensor.decensor(video.category?[i].category)}';

                                  try {
                                    await _home.onMenuChange(kMenuExplore);
                                    await _explore.openSelection(kCategory, name, newTab: newTab);
                                  } catch (_) {}
                                }),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // series
                          if (!video.series.isEmptyOrNull) ...[
                            'Series:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${HelperDecensor.decensor(video.series)}'.text.underline.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16).onInkTap(() async {
                              // ** on series clicked
                              final newTab = PageExploreController.isNewTabModifierPressed;
                              try {
                                await Overlayment.dismissLast();
                                final check = await DBVideos.getBySeries(video.series ?? '');
                                final name = '${HelperDecensor.decensor(video.series)}';

                                if (check.isNotEmpty) {
                                  await _home.onMenuChange(kMenuExplore);
                                  await _explore.openSelection(kSeries, name, newTab: newTab);
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
                            '${video.releaseDateFormated}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // duration
                          if (video.duration != 0) ...[
                            'Duration:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.durationFormated}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // label
                          if (!video.label.isEmptyOrNull) ...[
                            'Label:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.label}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // studio
                          if (!video.studio.isEmptyOrNull) ...[
                            'Studio:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.studio}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // director
                          if (!video.director.isEmptyOrNull) ...[
                            'Director:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.director}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
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
      final fixCode = HelperMisc.resolveVideoCode(videoCode: item.videoCode, videoPath: item.videoPath, title: item.title);
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
        color: AppColor.panel,
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
                MediaStack(
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
                    return MediaStack(
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
      final fixCode = HelperMisc.resolveVideoCode(videoCode: item.videoCode, videoPath: item.videoPath, title: item.title);
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
        child: MediaStack(
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
        color: AppColor.panel,
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
    bool matchAllCategories = false,
    bool Function()? isAvailable,
  }) async {
    try {
      await state.ensureOptionsLoaded(
        loadActresses: showActressName ?? true,
        loadCategories: showCategories ?? true,
      );
    } catch (e) {
      AppLog.logE('Failed to load filter options: $e');
      await HelperToast.error('Unable to load filter options. Please try again.');
      return;
    }
    if (Get.context == null || (isAvailable != null && !isAvailable())) return;

    final values = await showDialog<_VideoFilterValues>(
      context: Get.context!,
      builder: (context) => _VideoFilterDialog(
        state: state,
        widthFactor: widthFactor,
        showVideoCode: showVideoCode ?? true,
        showActressName: showActressName ?? true,
        showCategories: showCategories ?? true,
        showYears: showYears ?? true,
        matchAllCategories: matchAllCategories,
      ),
    );
    if (values == null || (isAvailable != null && !isAvailable())) return;

    state.tecVideoCode.text = values.videoCode;
    state.tecActressName.text = values.actress;
    state.tecCategory.clear();
    state.categoriesSelected.assignAll(values.categories);
    state.currentRange.value = values.years;
    state.durationMin.value = values.durationMin;
    state.durationMax.value = values.durationMax;
    state.isFiltered.value = state.hasFilters;
    if (applyLocalFilter) videos.assignAll(state.apply(allVideos, adapter));
    if (!state.hasFilters) {
      if (onReset != null) await onReset();
    } else if (onApplied != null) {
      await onApplied(applyLocalFilter ? videos.toList() : <T>[]);
    }
  }
}

class VideoFilterAdapter<T> {
  const VideoFilterAdapter({
    required this.videoCode,
    required this.actresses,
    required this.categories,
    required this.releaseDate,
    this.durationMinutes,
  });

  final String Function(T video) videoCode;
  final Iterable<String> Function(T video) actresses;
  final Iterable<String> Function(T video) categories;
  final String? Function(T video) releaseDate;
  final num? Function(T video)? durationMinutes;
}

class VideoFilterState {
  VideoFilterState({RxBool? isFiltered}) : isFiltered = isFiltered ?? false.obs;

  final durationMin = RxnInt();
  final durationMax = RxnInt();
  final RxBool isFiltered;
  final tecVideoCode = TextEditingController();
  final tecActressName = TextEditingController();
  final tecCategory = TextEditingController();
  final actresses = <String>[].obs;
  final categories = <String>[].obs;
  final categoriesSelected = <String>[].obs;
  final currentRange = RangeValues(2000, DateTime.now().year.toDouble()).obs;

  Future<void> ensureOptionsLoaded({bool loadActresses = true, bool loadCategories = true}) async {
    if (loadActresses && actresses.isEmpty) {
      await DBR18.getAllActress().then((actress) {
        for (var i = 0; i < actress.length; i++) {
          actresses.add('${actress[i]['name_romaji']}');
        }
        actresses.unique();
      });
    }

    if (loadCategories && categories.isEmpty) {
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
    categoriesSelected.clear();
    currentRange.value = RangeValues(2000, DateTime.now().year.toDouble());
    durationMin.value = null;
    durationMax.value = null;
    isFiltered.value = false;
  }

  bool get hasDurationFilter => durationMin.value != null || durationMax.value != null;

  bool get hasYearFilter => currentRange.value.start > 2000 || currentRange.value.end < DateTime.now().year;

  bool get hasFilters => tecVideoCode.text.trim().isNotEmpty || tecActressName.text.trim().isNotEmpty || categoriesSelected.isNotEmpty || hasYearFilter || hasDurationFilter;

  List<T> apply<T>(List<T> allVideos, VideoFilterAdapter<T> adapter) {
    var filteredVideos = allVideos.toList();

    if (tecVideoCode.text.isNotBlank) {
      final query = tecVideoCode.text.trim().toLowerCase();
      filteredVideos = filteredVideos.where((video) => adapter.videoCode(video).toLowerCase().contains(query)).toList();
    }

    if (tecActressName.text.isNotBlank) {
      final query = tecActressName.text.trim().toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        return adapter.actresses(video).any((name) => name.toLowerCase().contains(query));
      }).toList();
    }

    if (categoriesSelected.isNotEmpty) {
      final selected = categoriesSelected.toSet();
      filteredVideos = filteredVideos.where((video) {
        return adapter.categories(video).any((category) => category.isNotEmpty && selected.contains(category));
      }).toList();
    }

    if (hasYearFilter) {
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

    if (hasDurationFilter) {
      filteredVideos = filteredVideos.where((video) {
        final minutes = adapter.durationMinutes?.call(video);
        return minutes != null && minutes.isFinite && minutes > 0
            && (durationMin.value == null || minutes >= durationMin.value!)
            && (durationMax.value == null || minutes <= durationMax.value!);
      }).toList();
    }
    isFiltered.value = hasFilters;
    return filteredVideos;
  }
}

typedef _VideoFilterValues = ({String videoCode, String actress, List<String> categories, RangeValues years, int? durationMin, int? durationMax});

class _VideoFilterDialog extends StatefulWidget {
  const _VideoFilterDialog({required this.state, required this.widthFactor, required this.showVideoCode, required this.showActressName, required this.showCategories, required this.showYears, required this.matchAllCategories});

  final VideoFilterState state;
  final double widthFactor;
  final bool showVideoCode;
  final bool showActressName;
  final bool showCategories;
  final bool showYears;
  final bool matchAllCategories;

  @override
  State<_VideoFilterDialog> createState() => _VideoFilterDialogState();
}

class _VideoFilterDialogState extends State<_VideoFilterDialog> {
  late final _code = TextEditingController(text: widget.state.tecVideoCode.text);
  late final _actress = TextEditingController(text: widget.state.tecActressName.text);
  final _category = TextEditingController();
  late final _categories = widget.state.categoriesSelected.toList();
  late final _durationMin = TextEditingController(text: widget.state.durationMin.value?.toString() ?? '');
  late final _durationMax = TextEditingController(text: widget.state.durationMax.value?.toString() ?? '');
  String? _durationError;
  late RangeValues _years = widget.state.currentRange.value;

  @override
  void dispose() {
    _code.dispose();
    _actress.dispose();
    _category.dispose();
    _durationMin.dispose();
    _durationMax.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _code.clear();
      _actress.clear();
      _category.clear();
      _categories.clear();
      _durationMin.clear();
      _durationMax.clear();
      _durationError = null;
      _years = RangeValues(2000, DateTime.now().year.toDouble());
    });
  }

  void _apply() {
    final min = int.tryParse(_durationMin.text.trim());
    final max = int.tryParse(_durationMax.text.trim());
    if ((_durationMin.text.trim().isNotEmpty && (min == null || min < 0))
        || (_durationMax.text.trim().isNotEmpty && (max == null || max <= 0))
        || (min != null && max != null && min > max)) {
      setState(() => _durationError = 'Enter valid minutes; max must be at least min.');
      return;
    }
    Navigator.of(context).pop<_VideoFilterValues>((
      durationMin: min, durationMax: max,
      videoCode: widget.showVideoCode ? _code.text.trim() : '',
      actress: widget.showActressName ? _actress.text.trim() : '',
      categories: widget.showCategories ? List<String>.from(_categories) : <String>[],
      years: widget.showYears ? _years : RangeValues(2000, DateTime.now().year.toDouble()),
    ));
  }

  static Color get _accent => AppColor.accent;
  static Color get _muted => AppColor.muted;

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.text)),
  );

  Widget _field(TextEditingController controller, String placeholder, {FocusNode? focusNode, bool submit = false}) => CupertinoTextField(
    controller: controller,
    focusNode: focusNode,
    placeholder: placeholder,
    clearButtonMode: OverlayVisibilityMode.editing,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: AppColor.container,
      border: Border.all(color: AppColor.border),
      borderRadius: BorderRadius.circular(8),
    ),
    style: TextStyle(color: AppColor.text, fontSize: 12),
    placeholderStyle: TextStyle(color: AppColor.muted, fontSize: 12),
    onSubmitted: submit ? (_) => _apply() : null,
  );

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final year = DateTime.now().year.toDouble();
    final codeField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Video code'),
      _field(_code, 'Contains video code...', submit: true),
    ]);
    final actressField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Actress'),
      ExAutoComplate(
        controller: _actress,
        items: widget.state.actresses,
        maxHeight: 160,
        emptyText: 'No suggestions. You can still filter by this name.',
        fieldBuilder: (_, controller, focus) => _field(controller, 'Search actress name...', focusNode: focus),
        onSelected: (name) => _actress.text = name,
      ),
    ]);
    return Dialog(
      backgroundColor: AppColor.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColor.border)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * widget.widthFactor).clamp(440, 520),
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.tune_rounded, size: 19, color: _accent),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Filter', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColor.text)),
                  SizedBox(height: 3),
                  Text('Find exactly what you’re looking for', style: TextStyle(fontSize: 11, color: _muted)),
                ])),
                IconButton(tooltip: 'Cancel', onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, size: 17, color: _muted)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.showVideoCode || widget.showActressName) ...[
                      LayoutBuilder(builder: (context, constraints) {
                        if (widget.showVideoCode && widget.showActressName && constraints.maxWidth >= 380) {
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: codeField),
                            const SizedBox(width: 12),
                            Expanded(child: actressField),
                          ]);
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (widget.showVideoCode) codeField,
                          if (widget.showVideoCode && widget.showActressName) const SizedBox(height: 14),
                          if (widget.showActressName) actressField,
                        ]);
                      }),
                      const SizedBox(height: 20),
                    ],
                    if (widget.showCategories) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(10)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text('Categories', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                            Tooltip(
                              message: widget.matchAllCategories ? 'Videos must match all selected categories' : 'Videos can match any selected category',
                              child: Text(widget.matchAllCategories ? 'Match all' : 'Match any', style: TextStyle(fontSize: 10, color: _accent)),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          ExAutoComplate(
                            controller: _category,
                            items: widget.state.categories.where((category) => !_categories.contains(category)).toList(),
                            maxHeight: 160,
                            emptyText: 'No more matching categories.',
                            fieldBuilder: (_, controller, focus) => _field(controller, 'Search and add categories...', focusNode: focus),
                            onSelected: (category) {
                              setState(() {
                                if (!_categories.contains(category)) _categories.add(category);
                                _category.clear();
                              });
                            },
                          ),
                          if (_categories.isNotEmpty) Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _categories.map((category) => InputChip(
                                label: Text(category, style: TextStyle(fontSize: 11, color: _accent)),
                                backgroundColor: AppColor.selected,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                visualDensity: VisualDensity.compact,
                                deleteIcon: Icon(Icons.close, size: 13, color: _accent),
                                onDeleted: () => setState(() => _categories.remove(category)),
                              )).toList(),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _label('Duration (minutes)'),
                    Row(children: [
                      Expanded(child: CupertinoTextField(
                        key: const ValueKey('filter-duration-min'), controller: _durationMin,
                        placeholder: 'Min · Any', keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        style: TextStyle(color: AppColor.text, fontSize: 12),
                        placeholderStyle: TextStyle(color: _muted, fontSize: 12),
                        decoration: BoxDecoration(color: AppColor.container, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(8)),
                      )),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('–', style: TextStyle(color: _muted))),
                      Expanded(child: CupertinoTextField(
                        key: const ValueKey('filter-duration-max'), controller: _durationMax,
                        placeholder: 'Max · Any', keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        style: TextStyle(color: AppColor.text, fontSize: 12),
                        placeholderStyle: TextStyle(color: _muted, fontSize: 12),
                        decoration: BoxDecoration(color: AppColor.container, border: Border.all(color: AppColor.border), borderRadius: BorderRadius.circular(8)),
                      )),
                    ]),
                    if (_durationError != null) Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(_durationError!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    if (widget.showYears) ...[
                      Row(children: [
                        Expanded(child: Text('Release year', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                        Text(_years.start == 2000 && _years.end == year ? 'Any year' : '${_years.start.toInt()} – ${_years.end.toInt()}', style: TextStyle(fontSize: 11, color: _accent)),
                      ]),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: _accent,
                          inactiveTrackColor: AppColor.border,
                          thumbColor: _accent,
                          activeTickMarkColor: Colors.transparent,
                          inactiveTickMarkColor: Colors.transparent,
                          overlayColor: _accent.withAlpha(24),
                          rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: RangeSlider(
                          values: _years,
                          min: 2000,
                          max: year,
                          divisions: (year - 2000).toInt(),
                          labels: RangeLabels('${_years.start.toInt()}', '${_years.end.toInt()}'),
                          onChanged: (values) => setState(() => _years = values),
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('2000', style: TextStyle(fontSize: 10, color: _muted)),
                        Text('${year.toInt()}', style: TextStyle(fontSize: 10, color: _muted)),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: AppColor.container, border: Border(top: BorderSide(color: AppColor.border))),
              child: Row(children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: _muted, textStyle: TextStyle(fontSize: 12)),
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColor.text, textStyle: TextStyle(fontSize: 12)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: AppColor.onAccent,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
