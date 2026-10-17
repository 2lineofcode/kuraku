import 'dart:io';
import 'dart:math';

import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';

import '../../env.g.dart';
import '../core/app_color.dart';
import '../core/app_logging.dart';
import '../core/app_pref.dart';
import '../core/app_translations.dart';
import '../core/const.dart';
import '../data/api/api_javtrailers.dart';
import '../data/api/api_kuraku.dart';
import '../data/database/db_r18.dart';
import '../data/database/db_search_site.dart';
import '../data/database/db_videos.dart';
import '../data/models/__kuraku_search_entity.dart';
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
import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_desktop_trailer.dart';
import '../modules/widgets/widget_download_method.dart';
import '../modules/widgets/widget_keyboard_shortcuts.dart';
import '../modules/widgets/widget_screenshot_viewer.dart';
import '../modules/widgets/widget_style.dart';
import '../modules/widgets/widget_surfaces.dart';
import '../modules/widgets/widget_thumbnail.dart';
import '../modules/widgets/widget_title_translation.dart';
import '../routes/app_pages.dart';
import 'helper.dart';

mixin HelperOpener {
  // open folder
  static Future<void> openFolder(String path) async {
    try {
      if (path.isEmpty || await FileSystemEntity.type(path) == FileSystemEntityType.notFound) throw FileSystemException('File is unavailable', path);
      final target = await FileSystemEntity.isDirectory(path) ? path : p.dirname(path);
      final result = Platform.isWindows
          ? await Process.run('explorer.exe', [if (!await FileSystemEntity.isDirectory(path)) '/select,', path])
          : Platform.isLinux
          ? await Process.run('xdg-open', [target])
          : await Process.run('open', ['-R', path]);
      if (!Platform.isWindows && result.exitCode != 0) throw FileSystemException('${result.stderr}', path);
    } catch (e) {
      await HelperToast.error('File does not exist at path: @{path}'.trNamed({'path': path}));
    }
  }

  static Future<void> openFilePath(String path) => openFolder(path);

  static Future<void> openVideoPlaylist(List<Videos> videos) async {
    final playableVideos = videos.where((video) {
      final path = (video.videoPath ?? '').trim();
      return path.isNotEmpty && File(path).existsSync();
    }).toList();
    if (playableVideos.isEmpty) {
      await HelperToast.warn('No playable video found. Check your external drive connection.'.tr);
      return;
    }
    await openVideoFile(playableVideos.first, playlist: playableVideos);
  }

  // open video file -> direct default video player
  static Future<void> openVideoFile(Videos video, {List<Videos>? playlist}) async {
    final _defaultPlayer = AppPref.getDefaultPlayer();

    if (_defaultPlayer == 'In App') {
      final controller = Get.isRegistered<PlayerController>()
          ? Get.find<PlayerController>()
          : Get.put<PlayerController>(PlayerController(), permanent: true);

      final playablePlaylist = playlist?.where((item) {
        final path = (item.videoPath ?? '').trim();
        return path.isNotEmpty && File(path).existsSync();
      }).toList();
      final started = await controller.startPlayback(video, playlist: playablePlaylist);
      if (!started) return;

      controller.exitMiniMode();
      if (Get.currentRoute != Routes.PLAYER) {
        await Get.toNamed(Routes.PLAYER);
      } else {
        controller.requestFocusOnPlayer();
      }
    } else {
      try {
        if (Platform.isWindows) {
          final opened = await launchUrlString(Uri.file(video.videoPath!).toString(), mode: LaunchMode.externalApplication);
          if (!opened) throw StateError('No application could open the file');
        } else {
          final result = await Process.run(Platform.isLinux ? 'xdg-open' : 'open', [video.videoPath ?? '']);
          if (result.exitCode != 0) throw StateError('${result.stderr}');
        }
        await DBVideos.updateViewCount(video);
        await Get.find<PageHomeController>().getListMostWatch();
      } catch (e) {
        await HelperToast.error('$e');
      }
    }
  }

  // ────────────────────────────────────────────────────────────────
  // **
  // ────────────────────────────────────────────────────────────────
  static String downloadUrlForVideo(String code, {String? sourceUrl, String? searchEngine}) {
    if (searchEngine == null && sourceUrl != null && sourceUrl.trim().isNotEmpty) {
      final uri = Uri.tryParse(sourceUrl.trim());
      if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        throw ArgumentError('Invalid download source URL'.tr);
      }
      return uri.toString();
    }
    return DBSearchSite.resolve(searchEngine ?? AppPref.getDefaultSearchEngine()).urlFor(code, download: true);
  }

  static Future<void> openVideoInfo(dynamic item, {List<dynamic>? items}) async {
    if (item is Videos) {
      await HomePanelVideoInfo.open(item, items: items);
      return;
    }
    final source = List<dynamic>.of(items ?? [item]);
    final itemIndex = screenshotItemIndex(item, source);
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
      if (source is KurakuSearchResult) return source.videoCode ?? '';
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
    if (dataVideo == null && item is KurakuSearchResult) {
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
      if (resolvedCode.isEmpty) throw Exception('empty video code'.tr);
      final x = await DBVideos.getByCode(resolvedCode);
      if (x.videoCode.isNotEmptyAndNotNull && (item is! KurakuSearchResult || item.sourceUrl.isEmptyOrNull)) {
        HelperLoading.dismiss();
        await HomePanelVideoInfo.open(x, items: source, itemIndex: itemIndex);
        return;
      }
    } catch (_) {}

    // prefix
    video.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
    video.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
    video.director = dataDirector?['director'] ?? '';
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
                  HelperOpener.openScreenshot(video, items: source, itemIndex: itemIndex);
                  Overlayment.dismissLast();
                }
              }
            },
            child: VStack(
              [
                ExThumbnail(
                  imageUrl: video.fanArt,
                  screenshotItems: source, screenshotItemIndex: itemIndex,
                  videoPath: video.videoPath,
                  width: 300,
                  height: 200,
                  fitMemory: BoxFit.fitHeight,
                  fitUrl: BoxFit.contain,
                ).color(AppColor.selected).onInkTap(() => openScreenshot(video, items: source, itemIndex: itemIndex)),
                VStack(
                  [
                    '${video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title.maxWords(3)}'.text.maxLines(2).align(TextAlign.center).bold.makeCentered().onInkTap(() {
                      HelperMisc.copyToClipboard(video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title, showToast: true);
                    }).pSymmetric(v: 8),
                    TitleTranslation(title: video.title ?? '', child: Obx(
                      () => _translatedTitle.value.text.align(TextAlign.center).size(10).minFontSize(10).makeCentered().onInkTap(
                        () async {
                          HelperMisc.copyToClipboard(video.title, showToast: true);
                        },
                      ),
                    ).tooltip(video.videoPath ?? '')),
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
                      child: AppIconButton(
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.iconSize),
                        onPressed: () async {
                          await openScreenshot(item, items: source, itemIndex: itemIndex);
                        },
                      ),
                    ).pOnly(right: 8).tooltip('Screenshot'.tr),

                    // download
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: AppIconButton(
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload01, size: AppStyle.iconSize),
                        onPressed: () async {
                          WidgetsBinding.instance.scheduleFrame();
                          final selection = await Overlayment.show<({String method, String? engine})>(
                            context: Get.context,
                            OverWindow(
                              name: 'download-method',
                              alignment: Alignment.center,
                              animation: const OverFadeAnimation(durationMilliseconds: 0, reverseDurationMilliseconds: 0),
                              backgroundSettings: const BackgroundSettings(),
                              decoration: BoxDecoration(
                                color: AppColor.panel,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColor.border),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))],
                              ),
                              child: DownloadMethodDialog(
                                defaultEngine: AppPref.getDefaultSearchEngine(),
                                hasSourceUrl: item is KurakuSearchResult && item.sourceUrl.isNotEmptyAndNotNull,
                                onSelected: (selection) => Overlayment.dismissName('download-method', result: selection),
                              ),
                            ),
                          );
                          if (selection == null) return;
                          final method = selection.method;
                          await Overlayment.dismissLast();

                          final url = downloadUrlForVideo(video.videoCode ?? '', sourceUrl: item is KurakuSearchResult ? item.sourceUrl : null, searchEngine: selection.engine);

                          if (method == 'native') {
                            Get.find<PageDownloadController>().downloadWebsite(url);
                          } else {
                            try {
                              final target = method == 'downie' ? 'downie://XUOpenURL?url=${Uri.encodeComponent(url)}' : url;
                              final opened = await launchUrlString(target, mode: LaunchMode.externalApplication);
                              if (!opened) throw StateError('No application could open the URL'.tr);
                            } catch (e) {
                              await HelperToast.error('Unable to open @{URL}: @{e}'.trNamed({'URL': '${method == 'downie' ? 'Downie' : 'URL'}', 'e': '$e'}));
                              return;
                            }
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
                    ).pOnly(right: 8).tooltip('Download'.tr),

                    // trailer
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: AppIconButton(
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedVideo01, size: AppStyle.iconSize),
                        onPressed: () async => {await Overlayment.dismissLast(), await openTrailer(item),}
                      ),
                    ).pOnly(right: 8).tooltip('Trailer'.tr),
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
                            HugeIcon(icon: HugeIcons.strokeRoundedSourceCode, size: AppStyle.iconSize).pOnly(right: 8),
                            'Metadata'.tr.text.size(14).bold.make(),
                          ]).pOnly(bottom: 16),

                          // actress
                          if (!video.actress.isEmptyOrNull) ...[
                            'Actress:'.tr.text.size(12).bold.make().pOnly(bottom: 4),
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
                            'Category:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
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
                            'Series:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
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
                            'Release Date:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.releaseDateFormated}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // duration
                          if (video.duration != 0) ...[
                            'Duration:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.durationFormated}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // label
                          if (!video.label.isEmptyOrNull) ...[
                            'Label:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.label}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // studio
                          if (!video.studio.isEmptyOrNull) ...[
                            'Studio:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.studio}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ],

                          // director
                          if (!video.director.isEmptyOrNull) ...[
                            'Director:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
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

  static int screenshotItemIndex(dynamic item, List<dynamic> items) {
    final index = items.indexOf(item);
    if (index >= 0) return index;
    String code(dynamic value) {
      if (value is Videos) return HelperMisc.resolveVideoCode(videoCode: value.videoCode, videoPath: value.videoPath, title: value.title);
      if (value is KurakuSearchResult) return value.videoCode?.getVideoCode() ?? '';
      return value is Map ? '${value['video_code'] ?? ''}' : '';
    }
    if (item is Videos && (item.videoPath ?? '').isNotEmpty) {
      final pathIndex = items.indexWhere((value) => value is Videos && value.videoPath == item.videoPath);
      if (pathIndex >= 0) return pathIndex;
    }
    final currentCode = code(item);
    return currentCode.isEmpty ? -1 : items.indexWhere((value) => code(value) == currentCode);
  }

  static Future<Videos> resolveScreenshotVideo(dynamic item, {bool localFrames = false}) async {
    if (localFrames && item is Videos) return item;
    final String code;
    if (item is KurakuSearchResult) {
      code = item.videoCode?.getVideoCode() ?? '';
    } else if (item is Videos) {
      code = HelperMisc.resolveVideoCode(videoCode: item.videoCode, videoPath: item.videoPath, title: item.title);
    } else {
      code = item['video_code'];
    }
    final data = await DBR18.getVideo(code);
    final video = Videos.fromJson(data ?? {});
    if ((video.videoCode ?? '').trim().isEmpty) video.videoCode = code;
    if ((video.fanArt ?? '').trim().isEmpty) {
      final cover = item is Videos ? item.fanArt : item is KurakuSearchResult ? item.fanArt : item['fan_art'];
      video.fanArt = [data?['jacket_full_url'], cover, if (item is Map) item['jacket_full_url']]
          .map((value) => '${value ?? ''}'.trim()).firstWhere((value) => value.isNotEmpty, orElse: () => '');
    }
    if (data?['sslast'] != null && data?['ssfirst'] != null) {
      final total = int.tryParse(data!['sslast'].toString().split('-').last) ?? 0;
      final filename = data['ssfirst'].toString();
      final base = filename.contains('jp-') ? filename.removeLast(1) : '${filename.allBefore('-')}jp-';
      video.screenshot = [for (var i = 1; i <= total; i++) '$base$i'];
    }
    return video;
  }

  static Future<void> openScreenshot(dynamic item, {List<dynamic>? items, int? itemIndex, bool localFrames = false}) async {
    final source = List<dynamic>.of(items ?? [item]);
    final index = itemIndex ?? screenshotItemIndex(item, source);
    late Videos video;
    HelperLoading.show();
    try {
      video = await resolveScreenshotVideo(item, localFrames: localFrames);
    } catch (e) {
      AppLog.logW('openScreenshot: $e');
      HelperLoading.dismiss();
      await HelperToast.warn('Failed to load screenshots'.tr);
      return;
    }
    HelperLoading.dismiss();
    final viewerKey = GlobalKey<ScreenshotViewerState>();
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
        actions: OverlayActions(onReady: () async => viewerKey.currentState?.requestFocus()),
        child: ScreenshotViewer(
          key: viewerKey,
          video: video, items: source, itemIndex: index, localFrames: localFrames,
          loadVideo: (value) => resolveScreenshotVideo(value, localFrames: localFrames),
          onClose: () => Overlayment.dismissLast(),
          onWarning: (message) => HelperToast.warn(message.tr),
        ),
      ),
    );
  }

  static bool _isOpeningTrailer = false;

  static Future<Videos> resolveTrailerVideo(dynamic item) async {
    final Videos video;
    if (item is Videos) {
      video = Videos(videoCode: HelperMisc.resolveVideoCode(videoCode: item.videoCode, videoPath: item.videoPath, title: item.title), title: item.title, trailer: item.trailer);
    } else if (item is KurakuSearchResult) {
      video = Videos(videoCode: item.videoCode, title: item.title, trailer: item.trailer);
    } else if (item is Map) {
      video = Videos(videoCode: item['video_code']?.toString(), title: item['title']?.toString(), trailer: item['trailer']?.toString());
    } else {
      throw ArgumentError('Unsupported trailer item'.tr);
    }

    video.videoCode = (video.videoCode ?? '').trim().toUpperCase();
    video.trailer = (video.trailer ?? '').trim();
    if (video.trailer!.isNotEmpty || video.videoCode!.isEmpty) return video;
    final data = await DBR18.getVideo(video.videoCode!);
    return data == null ? video : Videos.fromJson(data);
  }

  static List<String> trailerUrls(String url) {
    url = url.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || ['www.dmm.co.jp', 'www.dmm.com'].contains(uri.host)) return [];
    if (url.startsWith(Env.vidUrl) || uri.host == 'media.javtrailers.com') return [url];
    return [url, url.genTrailerUrl()];
  }

  static Future<void> openTrailer(dynamic item) async {
    if (_isOpeningTrailer) return;
    _isOpeningTrailer = true;
    VideoPlayerController? player;
    ChewieController? chewie;
    var loading = true;
    var cancelled = false;
    try {
      HelperLoading.show(isDismissible: false, cancelCallback: () {
        cancelled = true;
        loading = false;
        HelperLoading.dismiss();
      });
      final video = await resolveTrailerVideo(item);
      if (cancelled) return;
      video.trailer = await ApiKuraku.resolveTrailerUrl(video.trailer ?? '', code: video.videoCode ?? '');
      if (cancelled) return;
      final urls = trailerUrls(video.trailer ?? '');
      if (urls.isEmpty) {
        throw StateError('Trailer not found or URL is invalid'.tr);
      }

      if ([TargetPlatform.linux, TargetPlatform.windows].contains(defaultTargetPlatform)) {
        HelperLoading.dismiss();
        loading = false;
        await Get.dialog<void>(DesktopTrailer(video: video, urls: urls));
        return;
      }
      for (final url in urls) {
        player = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: Uri.parse(url).host == 'media.javtrailers.com' ? ApiJavTrailers.headers : const {},
          formatHint: Uri.parse(video.trailer!.trim()).path.toLowerCase().endsWith('.m3u8') ? VideoFormat.hls : null,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
        );
        try {
          await player.initialize().timeout(const Duration(seconds: 20));
          break;
        } catch (e) {
          await player.dispose();
          player = null;
          if (cancelled) return;
          AppLog.logW('Trailer initialization failed (${video.videoCode}, $url): $e');
          if (url == urls.last) rethrow;
        }
      }
      if (cancelled) return;
      final controller = player!;
      await controller.setPlaybackSpeed(1.1);
      await controller.setVolume(0.1);
      if (cancelled) return;
      await controller.play();
      chewie = ChewieController(
        videoPlayerController: controller,
        allowFullScreen: false,
        showOptions: false,
        zoomAndPan: true,
        allowMuting: true,
        looping: false,
        customControls: ExChewieCustom(video: video, showTitle: false),
      );

      if (cancelled) return;
      HelperLoading.dismiss();
      loading = false;
      WidgetsBinding.instance.scheduleFrame();
      await Get.dialog<void>(Builder(
        builder: (context) {
          final size = MediaQuery.sizeOf(context);
          final padding = MediaQuery.paddingOf(context);
          // Keep room for playback controls on portrait trailers.
          final ratio = max(16 / 9, controller.value.aspectRatio);
          final availableHeight = max(0.0, size.height - padding.vertical - MediaQuery.viewInsetsOf(context).vertical - 76);
          final width = max(0.0, min(960.0, min(size.width - padding.horizontal - 32, availableHeight * ratio)));
          return AppDialog(
            child: SizedBox(width: width, child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 44, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Text('Trailer'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  if ((video.videoCode ?? '').isNotEmpty) ...[
                    Text(video.videoCode!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(HelperDecensor.decensor(video.title ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColor.muted))),
                  const SizedBox(width: 8),
                  AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close, size: AppStyle.iconSize),
                    onPressed: () => Get.back()),
                ]),
              )),
              SizedBox(width: width, height: width / ratio,
                // Chewie adds a full-video scrim on non-iOS themes.
                child: Theme(data: Theme.of(context).copyWith(platform: TargetPlatform.iOS),
                  child: ColoredBox(color: Colors.black, child: Chewie(controller: chewie!)))),
            ])),
          );
        },
      ));
    } catch (e) {
      if (loading) {
        HelperLoading.dismiss();
        loading = false;
      }
      if (!cancelled) {
        AppLog.logE('Unable to open trailer: $e');
        final message = e is PlatformException ? e.message ?? e.code : e.toString();
        await HelperToast.warn('Unable to play trailer: @{message}'.trNamed({'message': '$message'}), duration: 5.seconds);
      }
    } finally {
      if (loading) HelperLoading.dismiss();
      chewie?.dispose();
      try {
        await player?.dispose();
      } finally {
        _isOpeningTrailer = false;
      }
    }
  }

  static bool _isOpeningKeyboardShortcuts = false;

  static Future<void> openKeyboardShortcuts() async {
    if (Get.context == null || _isOpeningKeyboardShortcuts) return;
    _isOpeningKeyboardShortcuts = true;
    try {
      await showDialog<void>(
        context: Get.context!,
        builder: (context) => AppDialog(
          child: SizedBox(width: 520, child: KeyboardShortcutsPanel(onClose: () => Navigator.of(context).pop())),
        ),
      );
    } finally {
      _isOpeningKeyboardShortcuts = false;
    }
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
      await HelperToast.error('Unable to load filter options. Please try again.'.tr);
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
    state.blacklist.assignAll(values.blacklist);
    state.durationMin.value = values.durationMin;
    state.durationMax.value = values.durationMax;
    state.actressMode.value = values.actressMode;
    state.onlySeries.value = values.onlySeries;
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
    this.title,
    this.actressCount,
    this.series,
  });

  final String Function(T video) videoCode;
  final String? Function(T video)? title;
  final Iterable<String> Function(T video) actresses;
  final Iterable<String> Function(T video) categories;
  final String? Function(T video) releaseDate;
  final num? Function(T video)? durationMinutes;
  final int? Function(T video)? actressCount;
  final String? Function(T video)? series;
}

enum VideoBlacklistField { videoCode, title }

class VideoBlacklistRule {
  VideoBlacklistRule({required this.field, required this.pattern}) : regex = RegExp(pattern, caseSensitive: false) {
    if (pattern.trim().isEmpty) throw FormatException('Enter a regex pattern.'.tr);
  }

  final VideoBlacklistField field;
  final String pattern;
  final RegExp regex;

  Map<String, String> toJson() => {'field': field.name, 'pattern': pattern};

  static VideoBlacklistRule? fromJson(dynamic value) {
    if (value is! Map || value['pattern'] is! String) return null;
    final field = VideoBlacklistField.values.firstWhereOrNull((field) => field.name == value['field']);
    if (field == null) return null;
    try {
      return VideoBlacklistRule(field: field, pattern: value['pattern']);
    } on FormatException {
      return null;
    }
  }
}

class VideoFilterState {
  VideoFilterState({RxBool? isFiltered}) : isFiltered = isFiltered ?? false.obs;

  final blacklist = <VideoBlacklistRule>[].obs;
  final durationMin = RxnInt();
  final durationMax = RxnInt();
  final actressMode = ActressMode.all.obs;
  final onlySeries = false.obs;
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
    blacklist.clear();
    tecVideoCode.text = '';
    tecActressName.text = '';
    tecCategory.text = '';
    categoriesSelected.clear();
    currentRange.value = RangeValues(2000, DateTime.now().year.toDouble());
    durationMin.value = null;
    durationMax.value = null;
    actressMode.value = ActressMode.all;
    onlySeries.value = false;
    isFiltered.value = false;
  }

  bool get hasDurationFilter => durationMin.value != null || durationMax.value != null;

  bool get hasYearFilter => currentRange.value.start > 2000 || currentRange.value.end < DateTime.now().year;

  bool get hasFilters => blacklist.isNotEmpty || tecVideoCode.text.trim().isNotEmpty || tecActressName.text.trim().isNotEmpty || categoriesSelected.isNotEmpty || hasYearFilter || hasDurationFilter || actressMode.value != ActressMode.all || onlySeries.value;

  List<T> applyBlacklist<T>(List<T> allVideos, VideoFilterAdapter<T> adapter) => allVideos.where((video) {
    return !blacklist.any((rule) => rule.regex.hasMatch(
      HelperDecensor.decensor(rule.field == VideoBlacklistField.videoCode ? adapter.videoCode(video) : adapter.title?.call(video)),
    ));
  }).toList();

  List<Map<String, String>> get blacklistPreferences => blacklist.map((rule) => rule.toJson()).toList();

  void restoreBlacklist(dynamic value) {
    blacklist.assignAll(value is List ? value.map(VideoBlacklistRule.fromJson).whereType<VideoBlacklistRule>() : <VideoBlacklistRule>[]);
    if (blacklist.isNotEmpty) isFiltered.value = true;
  }

  List<T> apply<T>(List<T> allVideos, VideoFilterAdapter<T> adapter) {
    var filteredVideos = applyBlacklist(allVideos, adapter);

    if (actressMode.value != ActressMode.all) {
      filteredVideos = filteredVideos.where((video) {
        final count = adapter.actressCount?.call(video)
          ?? adapter.actresses(video).map((name) => name.trim().toLowerCase()).where((name) => name.isNotEmpty).toSet().length;
        return actressMode.value == ActressMode.single ? count == 1 : count > 1;
      }).toList();
    }
    if (onlySeries.value) {
      filteredVideos = filteredVideos.where((video) => adapter.series?.call(video)?.trim().isNotEmpty == true).toList();
    }

    if (tecVideoCode.text.isNotBlank) {
      final query = HelperDecensor.decensor(tecVideoCode.text).trim().toLowerCase();
      filteredVideos = filteredVideos.where((video) => HelperDecensor.decensor(adapter.videoCode(video)).toLowerCase().contains(query)).toList();
    }

    if (tecActressName.text.isNotBlank) {
      final query = HelperDecensor.decensor(tecActressName.text).trim().toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        return adapter.actresses(video).any((name) => HelperDecensor.decensor(name).toLowerCase().contains(query));
      }).toList();
    }

    if (categoriesSelected.isNotEmpty) {
      final selected = categoriesSelected.map(HelperDecensor.decensor).toSet();
      filteredVideos = filteredVideos.where((video) {
        return adapter.categories(video).any((category) => category.isNotEmpty && selected.contains(HelperDecensor.decensor(category)));
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

typedef _VideoFilterValues = ({String videoCode, String actress, List<String> categories, List<VideoBlacklistRule> blacklist, RangeValues years, int? durationMin, int? durationMax, ActressMode actressMode, bool onlySeries});

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
  late final _blacklist = widget.state.blacklist.map((rule) => (
    field: rule.field, controller: TextEditingController(text: rule.pattern),
  )).toList();
  final _blacklistErrors = <TextEditingController, String>{};
  String? _durationError;
  late RangeValues _years = widget.state.currentRange.value;
  late ActressMode _actressMode = widget.state.actressMode.value;
  late bool _onlySeries = widget.state.onlySeries.value;

  @override
  void dispose() {
    for (final rule in _blacklist) { rule.controller.dispose(); }
    _code.dispose();
    _actress.dispose();
    _category.dispose();
    _durationMin.dispose();
    _durationMax.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      for (final rule in _blacklist) { rule.controller.dispose(); }
      _blacklist.clear();
      _blacklistErrors.clear();
      _code.clear();
      _actress.clear();
      _category.clear();
      _categories.clear();
      _durationMin.clear();
      _durationMax.clear();
      _durationError = null;
      _years = RangeValues(2000, DateTime.now().year.toDouble());
      _actressMode = ActressMode.all;
      _onlySeries = false;
    });
    _apply();
  }

  void _apply() {
    final rules = <VideoBlacklistRule>[];
    _blacklistErrors.clear();
    for (final rule in _blacklist) {
      try {
        rules.add(VideoBlacklistRule(field: rule.field, pattern: rule.controller.text));
      } on FormatException {
        _blacklistErrors[rule.controller] = rule.controller.text.trim().isEmpty ? 'Enter a regex pattern.'.tr : 'Invalid regex pattern.'.tr;
      }
    }
    if (_blacklistErrors.isNotEmpty) {
      setState(() {});
      return;
    }
    final min = int.tryParse(_durationMin.text.trim());
    final max = int.tryParse(_durationMax.text.trim());
    if ((_durationMin.text.trim().isNotEmpty && (min == null || min < 0))
        || (_durationMax.text.trim().isNotEmpty && (max == null || max <= 0))
        || (min != null && max != null && min > max)) {
      setState(() => _durationError = 'Enter valid minutes; max must be at least min.'.tr);
      return;
    }
    Navigator.of(context).pop<_VideoFilterValues>((
      durationMin: min, durationMax: max, blacklist: rules,
      actressMode: _actressMode, onlySeries: _onlySeries,
      videoCode: widget.showVideoCode ? _code.text.trim() : '',
      actress: widget.showActressName ? _actress.text.trim() : '',
      categories: widget.showCategories ? List<String>.from(_categories) : <String>[],
      years: widget.showYears ? _years : RangeValues(2000, DateTime.now().year.toDouble()),
    ));
  }

  static Color get _muted => AppColor.muted;

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.text)),
  );

  Widget _field(TextEditingController controller, String placeholder, {FocusNode? focusNode, bool submit = false}) => AppTextField(
    controller: controller,
    focusNode: focusNode,
    placeholder: placeholder,
    clearButtonMode: OverlayVisibilityMode.editing,
    style: TextStyle(color: AppColor.text),
    placeholderStyle: TextStyle(color: AppColor.muted, fontSize: 12),
    onSubmitted: submit ? (_) => _apply() : null,
  );

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final year = DateTime.now().year.toDouble();
    final codeField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Video code'.tr),
      _field(_code, 'Contains video code...'.tr, submit: true),
    ]);
    final actressField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Actress'.tr),
      ExAutoComplate(
        controller: _actress,
        items: widget.state.actresses,
        displayStringForOption: HelperDecensor.decensor,
        maxHeight: 160,
        emptyText: 'No suggestions. You can still filter by this name.'.tr,
        fieldBuilder: (_, controller, focus) => _field(controller, 'Search actress name...'.tr, focusNode: focus),
        onSelected: (name) => _actress.text = HelperDecensor.decensor(name),
      ),
    ]);
    return AppDialog(
      backgroundColor: AppColor.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
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
                  child: HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: AppStyle.iconSize, color: AppColor.onSelected),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Filter'.tr, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColor.text)),
                  SizedBox(height: 3),
                  Text('Find exactly what you’re looking for'.tr, style: TextStyle(fontSize: 11, color: _muted)),
                ])),
                AppIconButton(tooltip: 'Cancel'.tr, onPressed: () => Navigator.pop(context), icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: _muted)),
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
                    Row(children: [
                      SizedBox(width: 92, child: Text('Actress count'.tr, style: TextStyle(fontSize: 12, color: AppColor.text))),
                      Expanded(child: AppDropdown<ActressMode>(
                        value: _actressMode, isExpanded: true, isDense: true,
                        style: TextStyle(fontSize: 12, color: AppColor.text),
                        items: const {ActressMode.all: 'All', ActressMode.single: 'Single Actress', ActressMode.multi: 'Multiple Actress'}
                          .entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value.tr))).toList(),
                        onChanged: (value) { if (value != null) setState(() => _actressMode = value); },
                      )),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      SizedBox(width: 92, child: Text('Series'.tr, style: TextStyle(fontSize: 12, color: AppColor.text))),
                      Expanded(child: AppDropdown<bool>(
                        value: _onlySeries, isExpanded: true, isDense: true,
                        style: TextStyle(fontSize: 12, color: AppColor.text),
                        items: const {false: 'All', true: 'Only videos with series'}
                          .entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value.tr))).toList(),
                        onChanged: (value) { if (value != null) setState(() => _onlySeries = value); },
                      )),
                    ]),
                    const SizedBox(height: 20),
                    if (widget.showCategories) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(10)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text('Categories'.tr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                            Tooltip(
                              message: widget.matchAllCategories ? 'Videos must match all selected categories'.tr : 'Videos can match any selected category'.tr,
                              child: Text(widget.matchAllCategories ? 'Match all'.tr : 'Match any'.tr, style: TextStyle(fontSize: 10, color: _muted)),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          ExAutoComplate(
                            controller: _category,
                            items: widget.state.categories.where((category) => !_categories.contains(category)).toList(),
                            displayStringForOption: HelperDecensor.decensor,
                            maxHeight: 160,
                            emptyText: 'No more matching categories.'.tr,
                            fieldBuilder: (_, controller, focus) => _field(controller, 'Search and add categories...'.tr, focusNode: focus),
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
                                label: Text(HelperDecensor.decensor(category), style: TextStyle(fontSize: 11, color: AppColor.onSelected)),
                                backgroundColor: AppColor.selected,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                visualDensity: VisualDensity.compact,
                                deleteIcon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: AppColor.onSelected),
                                onDeleted: () => setState(() => _categories.remove(category)),
                              )).toList(),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text('Blacklist'.tr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                          AppIconButton(
                            tooltip: 'Add blacklist rule'.tr, visualDensity: VisualDensity.compact,
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize, color: AppColor.text),
                            onPressed: () => setState(() => _blacklist.add((field: VideoBlacklistField.videoCode, controller: TextEditingController()))),
                          ),
                        ]),
                        Text('Hide matches · Regex · Case-insensitive'.tr, style: TextStyle(fontSize: 10, color: _muted)),
                        if (_blacklist.isEmpty) Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('No rules. Add one with +.'.tr, style: TextStyle(fontSize: 11, color: _muted)),
                        ),
                        for (var i = 0; i < _blacklist.length; i++) Padding(
                          key: ObjectKey(_blacklist[i].controller),
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              SizedBox(width: 100, child: AppDropdown<VideoBlacklistField>(
                                value: _blacklist[i].field, isExpanded: true, isDense: true,
                                dropdownColor: AppColor.panel,
                                style: TextStyle(color: AppColor.text),
                                items: {VideoBlacklistField.videoCode: 'Video Code'.tr, VideoBlacklistField.title: 'Title'.tr}.entries
                                    .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                                onChanged: (field) { if (field != null) setState(() => _blacklist[i] = (field: field, controller: _blacklist[i].controller)); },
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: _field(_blacklist[i].controller, _blacklist[i].field == VideoBlacklistField.videoCode ? 'AD-(.*)' : '(.*)VR(.*)')),
                              AppIconButton(
                                tooltip: 'Remove blacklist rule'.tr, visualDensity: VisualDensity.compact,
                                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: _muted),
                                onPressed: () => setState(() {
                                  final rule = _blacklist.removeAt(i);
                                  _blacklistErrors.remove(rule.controller);
                                  rule.controller.dispose();
                                }),
                              ),
                            ]),
                            if (_blacklistErrors[_blacklist[i].controller] != null) Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_blacklistErrors[_blacklist[i].controller]!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _label('Duration (minutes)'.tr),
                    Row(children: [
                      Expanded(child: AppTextField(
                        key: const ValueKey('filter-duration-min'), controller: _durationMin,
                        placeholder: 'Min · Any', keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: AppColor.text),
                        placeholderStyle: TextStyle(color: _muted, fontSize: 12),
                      )),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('–', style: TextStyle(color: _muted))),
                      Expanded(child: AppTextField(
                        key: const ValueKey('filter-duration-max'), controller: _durationMax,
                        placeholder: 'Max · Any', keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: AppColor.text),
                        placeholderStyle: TextStyle(color: _muted, fontSize: 12),
                      )),
                    ]),
                    if (_durationError != null) Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(_durationError!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    if (widget.showYears) ...[
                      Row(children: [
                        Expanded(child: Text('Release year'.tr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColor.text))),
                        Text(_years.start == 2000 && _years.end == year ? 'Any year'.tr : '${_years.start.toInt()} – ${_years.end.toInt()}', style: TextStyle(fontSize: 11, color: _muted)),
                      ]),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: _muted,
                          inactiveTrackColor: AppColor.border,
                          thumbColor: _muted,
                          activeTickMarkColor: Colors.transparent,
                          inactiveTickMarkColor: Colors.transparent,
                          overlayColor: _muted.withAlpha(24),
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
                AppButton(
                  style: TextButton.styleFrom(foregroundColor: _muted, textStyle: TextStyle(fontSize: 12)),
                  onPressed: _reset,
                  child: Text('Reset'.tr),
                ),
                const Spacer(),
                AppButton(
                  style: TextButton.styleFrom(foregroundColor: AppColor.text, textStyle: TextStyle(fontSize: 12)),
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'.tr),
                ),
                const SizedBox(width: 8),
                AppButton(variant: AppButtonVariant.filled,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _apply,
                  child: Text('Apply'.tr),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
