// ignore_for_file: deprecated_member_use

import 'dart:math' show max;

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:uicons_pro/uicons_pro.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import '../page_explore/page_explore_controller.dart';
import '../page_home/page_home_controller.dart';
import 'page_search_controller.dart';

mixin PageSearchOverlay {
  static Future<void> onItemTap(Videos video) async {
    final _controller = Get.find<PageSearchController>();
    final _mediaInfo = <String>[].obs;
    final _focusNode = FocusNode();

    // open overlay
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
                ).color(AppColor.selected).onInkTap(() => _openScreenshot(video)),
                VStack(
                  [
                    '${video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title.maxWords(3)}'.text.maxLines(2).align(TextAlign.center).bold.makeCentered().onInkTap(() {
                      HelperMisc.copyToClipboard(video.videoCode ?? '', showToast: true);
                    }).pSymmetric(v: 8),
                    '${video.title}'.text.align(TextAlign.center).size(10).minFontSize(10).maxLines(3).ellipsis.makeCentered().onInkTap(
                      () {
                        HelperMisc.copyToClipboard(video.title ?? '', showToast: true);
                      },
                    ).tooltip(video.videoPath ?? ''),

                    ExDivider().pSymmetric(v: 16),

                    // action
                    HStack(
                      [
                        Spacer(),
                        // play
                        Container(
                          decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                          child: IconButton(
                            icon: Icon(UIconsPro.regularRounded.play, size: 14),
                            onPressed: () => {
                              Overlayment.dismissLast(),
                              HelperOpener.openVideoFile(video),
                            },
                          ),
                        ).pOnly(right: 8),

                        // add to favorite
                        GetBuilder<PageSearchController>(
                          init: _controller,
                          builder: (b) => Container(
                            decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                            child: IconButton(
                              icon: video.isFavorite == 1 ? Icon(UIconsPro.solidRounded.star, size: 14, color: Vx.orange500) : Icon(UIconsPro.regularRounded.star, size: 14, color: null),
                              onPressed: () {
                                final current = video.isFavorite ?? 0;
                                if (current == 1) {
                                  DBVideos.removeFromFavorite(video);
                                } else {
                                  DBVideos.addToFavorite(video);
                                }
                                Get.find<PageHomeController>().getListFavorite();
                                b.update();
                              },
                            ),
                          ).pOnly(right: 8),
                        ),

                        // renew metadata
                        video.videoCode?.isNotBlank ?? false
                            ? Container(
                                decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                                child: IconButton(
                                  icon: Icon(UIconsPro.regularRounded.thought_bubble, size: 14),
                                  onPressed: () => _controller.renewMetadata(video),
                                ),
                              ).pOnly(right: 8)
                            : 0.heightBox,

                        Container(
                          decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                          child: IconButton(
                            icon: Icon(UIconsPro.regularRounded.folder, size: 16),
                            onPressed: () => HelperOpener.openFilePath(video.videoPath ?? ''),
                          ),
                        ).pOnly(right: 8),

                        Spacer(),
                      ],
                    ).pOnly(bottom: 16),
                  ],
                ).pSymmetric(h: 16),

                // metadata
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
                                    .tooltip(video.actress?[i].nameRomaji == '' ? '${KanaKit().toRomaji(video.actress?[i].nameKana ?? '')}' : '')
                                    .onInkTap(() async => await _onItemActressClick(video, i))
                                    .pOnly(right: 8),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // category
                          if (!video.category.isEmptyOrNull) ...[
                            'Category:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            Wrap(children: [
                              for (int i = 0; i < video.category!.length; i++) ...[
                                FutureBuilder(
                                  future: HelperMisc.decensor(video.category?[i].category ?? ''),
                                  builder: (context, snapshot) {
                                    return snapshot.hasData
                                        ? '${snapshot.data}'.text.neutral300.underline.size(11).minFontSize(11).make().onInkTap(() async {
                                            await _onItemCategoryClick(video, i);
                                          }).pOnly(right: 8)
                                        : 0.heightBox;
                                  },
                                ),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // series
                          if (!video.series.isEmptyOrNull) ...[
                            'Series:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            FutureBuilder(
                              future: HelperMisc.decensor(video.series ?? ''),
                              builder: (context, snapshot) {
                                return snapshot.hasData
                                    ? '${snapshot.data}'.text.underline.neutral300.size(11).minFontSize(11).make().onInkTap(() async {
                                        await _onItemSeriesClick(video);
                                      }).pOnly(bottom: 16)
                                    : 0.heightBox;
                              },
                            ),
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

                          // ~
                          GetBuilder(
                            init: _controller,
                            builder: (_) => _mediaInfo.isNotEmpty
                                ? VStack([
                                    // resolution
                                    'Res:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                                    '${_mediaInfo[0]}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),

                                    // filesize
                                    'File Size:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                                    '${_mediaInfo[2]}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),

                                    // duration (non jav)
                                    if (video.duration == 0) ...[
                                      'Duration:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                                      '${_mediaInfo[3]}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                                    ],   
                                  ])
                                : VStack([
                                    'Get More Info'.text.blue300.size(12).underline.make().onInkTap(() async {
                                      _mediaInfo.value = await _getMediaInfo(video.videoPath ?? '');
                                      if (_mediaInfo.length > 2) _controller.update();
                                    }).pOnly(bottom: 16),
                                  ]),
                          ),

                          // Path
                          'Path:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                          '${video.videoPath?.getLastSegments()}'.text.neutral300.ellipsis.size(11).minFontSize(11).make().color(Vx.neutral800).onInkTap(() async {
                            await _onItemVideoPathClick(video);
                          }).tooltip(video.videoPath ?? ''),

                          // added
                          'Added:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4, top: 16),
                          '${video.createdAt?.reformatDate()}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),

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

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~
  // ────────────────────────────────────────────────────────────────
  static Future<void> _openScreenshot(Videos video) async {
    final idxSelectedJav = 0.obs;
    final idxSelectedNonJav = 10.obs;
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
                // ** non jav
                if (video.screenshot.isEmptyOrNull) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    idxSelectedNonJav.value = idxSelectedNonJav.value - 10;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    idxSelectedNonJav.value = idxSelectedNonJav.value + 10;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    Overlayment.dismissLast();
                  }
                }

                // **  jav
                else {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    if (idxSelectedJav.value > 0) idxSelectedJav.value--;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    if (idxSelectedJav.value < video.screenshot!.length - 1) idxSelectedJav.value++;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    Overlayment.dismissLast();
                  }
                }
              }
            },
            child: VStack(
              [
                // ** non jav
                if (video.screenshot.isEmptyOrNull) ...[
                  Obx(
                    () => ExThumbnail(
                      imageUrl: '',
                      videoPath: video.videoPath,
                      width: max(Get.width * 90 / 100, 400),
                      height: max(Get.height * 80 / 100, 400) - 80,
                      fitMemory: BoxFit.contain,
                      position: idxSelectedNonJav.value,
                    ),
                  ),
                  Container(height: 5, color: AppColor.container),
                  ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final pos = max(index * ExRandom.between(60, 180), 3);
                      return ZStack(
                        [
                          ExThumbnail(
                            imageUrl: '',
                            videoPath: video.videoPath,
                            width: 120,
                            height: 70,
                            fitMemory: BoxFit.cover,
                            position: pos,
                          ).onInkTap(() => idxSelectedNonJav.value = pos).pOnly(right: 4),
                          Obx(
                            () => Container(
                              width: 120,
                              height: 70,
                              color: Colors.green.withAlpha(100),
                            ).onInkTap(() => idxSelectedNonJav.value = pos).pOnly(right: 4).hide(isVisible: idxSelectedNonJav.value == pos),
                          ),
                        ],
                      );
                    },
                  ).wh(double.infinity, 70),
                  Container(height: 5, color: AppColor.container),
                ]

                // ** jav
                else ...[
                  ZStack(
                    [
                      Obx(
                        () => Zoom(
                          width: max(Get.width * 90 / 100, 400),
                          height: max(Get.height * 80 / 100, 400) - 80,
                          child: ExThumbnail(
                            imageUrl: '${video.screenshot?[idxSelectedJav.value]}',
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
                          child: '${idxSelectedJav.value + 1}/${video.screenshot!.length}'.text.size(11).minFontSize(11).make().p4(),
                        ),
                      ).p12(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                          child: Icon(UIconsPro.regularRounded.arrow_small_right).p12(),
                        ).onInkTap(() {
                          if (idxSelectedJav.value < video.screenshot!.length - 1) {
                            idxSelectedJav.value++;
                          }
                        }),
                      ).positioned(right: 8, top: 0, bottom: 0),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
                          child: Icon(UIconsPro.regularRounded.arrow_small_left).p12(),
                        ).onInkTap(() {
                          if (idxSelectedJav.value > 0) {
                            idxSelectedJav.value--;
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
                      ).positioned(right: 8, top: 12, bottom: 0),
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
                            idxSelectedJav.value = index;
                          }).pOnly(right: 4),
                          Obx(
                            () => Container(
                              width: 120,
                              height: 70,
                              color: Colors.green.withAlpha(100),
                            ).onInkTap(() => idxSelectedJav.value = index).pOnly(right: 4).hide(isVisible: idxSelectedJav.value == index),
                          ),
                        ],
                      );
                    },
                  ).wh(double.infinity, 70),
                  Container(height: 5, color: AppColor.container),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _onItemActressClick(Videos video, int index) async {
    final name = '${video.actress?[index].nameRomaji == '' ? '${video.actress?[index].nameKana}' : '${video.actress?[index].nameRomaji}'}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.onFilterByChange('Actress');
    exploreC.tecSearch.text = name;
    exploreC.onOListSearch(name);
    await exploreC.onOListTap(exploreC.oListFiltered[0]);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemCategoryClick(Videos video, int index) async {
    final name = '${video.category?[index].category}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.onFilterByChange('Category');
    exploreC.tecSearch.text = name;
    exploreC.onOListSearch(name);
    await exploreC.onOListTap(exploreC.oListFiltered[0]);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemSeriesClick(Videos video) async {
    final name = '${video.series}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.onFilterByChange('Series');
    exploreC.tecSearch.text = name;
    exploreC.onOListSearch(name);
    await exploreC.onOListTap(exploreC.oListFiltered[0]);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemVideoPathClick(Videos video) async {
    final directory = p.dirname(video.videoPath ?? '');
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.onFilterByChange('Path');
    exploreC.tecSearch.text = directory;
    exploreC.onOListSearch(directory);
    await exploreC.onOListTap(exploreC.oListFiltered[0]);
    await Overlayment.dismissLast();
  }

  static Future<List<String>> _getMediaInfo(String path) async {
    final output = <String>[];
    HelperLoading.show();
    await FFprobeKit.getMediaInformation(path).then((value) async {
      HelperLoading.dismiss();
      final medinfo = value.getMediaInformation();
      final stream = value.getMediaInformation()?.getStreams().first;
      output.add('${stream?.getWidth()}x${stream?.getHeight()}'); // -- [0] width x height
      output.add('${stream?.getHeight()}p'); // -- [1] resolution
      output.add('${int.parse(medinfo!.getSize()!).toFileSize()}'); // -- [2] file size
      output.add('${HelperMisc.durationFormat2(num.parse(medinfo.getFormatProperties()!['duration'].toString()))}'); // -- [3] duration
    }).catchError((e) {
      HelperLoading.dismiss();
      HelperToast.error('Could not get media info, please check file path, $path');
    });

    return output;
  }
}
