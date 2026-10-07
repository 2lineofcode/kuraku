import 'dart:math' show max;

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import '../page_explore/page_explore_controller.dart';
import '../page_home/page_home_controller.dart';
import '../page_search/page_search_controller.dart';
import 'home_panel_metadata.dart';
import 'home_panel_playlist.dart';

mixin HomePanelVideoInfo {
  //
  static Future<void> open(Videos video) async {
    final _controller = Get.find<PageSearchController>();
    final _mediaInfo = <String>[].obs;
    final _translatedTitle = HelperDecensor.decensor(video.title ?? '').obs;
    final _focusNode = FocusNode();

    // open overlay
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        actions: OverlayActions(
          onReady: () async => _focusNode.requestFocus(),
        ),
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

                if (event.logicalKey == LogicalKeyboardKey.keyI) {
                  Overlayment.dismissLast();
                }

                if (event.logicalKey == LogicalKeyboardKey.period) {
                  HelperOpener.openVideoFile(video);
                  Overlayment.dismissLast();
                }
              }
            },
            child: VStack(
              [
                ZStack([
                  ExThumbnail(
                    imageUrl: video.fanArt,
                    videoPath: video.videoPath,
                    width: 300,
                    height: 200,
                    fitMemory: BoxFit.fitHeight,
                    fitUrl: BoxFit.contain,
                  ).color(AppColor.selected).onInkTap(() => _openScreenshot(video)),

                  // quality
                  if (video.quality.isNotEmptyAndNotNull) ...[
                    Container(
                      decoration: ExDecorator.box(borderRadius: 0, borderColor: Colors.transparent, fillColor: AppColor.black170),
                      child: '${HelperMisc.formatVideoQuality(video.quality ?? '').maxWords(1)} (${video.filesize?.toFileSizeFormat()})'.text.bold.amber500.size(11).minFontSize(11).make().p4().pSymmetric(h: 4),
                    ).cornerRadius(90).positioned(right: 4, bottom: 4),
                  ],
                ]),
                VStack(
                  [
                    '${video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title.maxWords(3)}'.text.maxLines(2).align(TextAlign.center).bold.makeCentered().onInkTap(() {
                      final textToCopy = video.videoCode.isNotEmptyAndNotNull ? video.videoCode! : video.title;
                      HelperMisc.copyToClipboard(textToCopy, showToast: true);
                    }).pSymmetric(v: 8),
                    Obx(
                      () => _translatedTitle.value.text
                          .align(TextAlign.center)
                          .size(10)
                          .minFontSize(10)
                          .makeCentered()
                          .onInkTap(
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

                    // ** action
                    HStack(
                      [
                        Spacer(),
                        // play
                        Container(
                          decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                          child: AppIconButton(
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: AppStyle.iconSize),
                            onPressed: () => {
                              Overlayment.dismissLast(),
                              HelperOpener.openVideoFile(video),
                            },
                          ),
                        ).pOnly(right: 8).tooltip('Play'.tr),

                        // add to favorite
                        GetBuilder<PageSearchController>(
                          init: _controller,
                          builder: (b) => Container(
                            decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                            child: AppIconButton(
                              icon: video.isFavorite == 1 ? HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: AppStyle.iconSize, color: Vx.orange500) : HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: AppStyle.iconSize, color: null),
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
                          ).pOnly(right: 8).tooltip('Add/Remove Favorite'.tr),
                        ),

                        // renew metadata
                        // video.videoCode?.isNotBlank ?? false
                        //     ?
                            Container(
                                decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                                child: AppIconButton(
                                  icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
                                  onPressed: () => _controller.renewMetadata(video),
                                ),
                              ).pOnly(right: 8).tooltip('Renew Metadata'.tr),
                            // : 0.heightBox,

                        Container(
                          decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                          child: AppIconButton(
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: AppStyle.iconSize),
                            onPressed: () => HelperOpener.openFilePath(video.videoPath ?? ''),
                          ),
                        ).pOnly(right: 8).tooltip('Open File Path'.tr),

                        Container(
                          decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                          child: AppIconButton(
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
                            onPressed: () {
                              final homeController = Get.find<HomeController>();
                              final isAdded = homeController.addToCart(video);
                              if (!isAdded) {
                                HelperToast.info('Already in panel cart'.tr);
                              }
                              Overlayment.dismissLast();
                            },
                          ),
                        ).pOnly(right: 8).tooltip('Add to Panel Cart'.tr),

                        Spacer(),
                      ],
                    ).pOnly(bottom: 16),
                  ],
                ).pSymmetric(h: 16),

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
                            '# Metadata'.tr.text.size(14).bold.make().expand(),

                            AppIconButton(
                              icon: HugeIcon(icon: HugeIcons.strokeRoundedPlayListFavourite02 , size: AppStyle.iconSize),
                              tooltip: 'Add To Playlist'.tr,
                              onPressed: () async {
                                await Overlayment.dismissLast();
                                await HomePanelPlaylist.showDialogAddToPlaylistItem([video]);
                              },
                            ),

                            AppIconButton(
                              icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit01 , size: AppStyle.iconSize),
                              tooltip: 'Edit Metadata'.tr,
                              onPressed: () async {
                                await Overlayment.dismissLast();
                                await HomePanelMetadata.open(video);
                              },
                            ),

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
                                    .tooltip(video.actress?[i].nameRomaji == '' ? '${KanaKit().toRomaji(video.actress?[i].nameKana ?? '')}' : '')
                                    .onInkTap(() async => await _onItemActressClick(video, i))
                                    .pOnly(right: 8),
                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // category
                          if (!video.category.isEmptyOrNull) ...[
                            'Category:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            Wrap(children: [
                              for (int i = 0; i < video.category!.length; i++) ...[
                                '${HelperDecensor.decensor(video.category?[i].category)}'.text.color(AppColor.muted).underline.size(11).minFontSize(11).make().onInkTap(() async {
                                  await _onItemCategoryClick(video, i);
                                }).pOnly(right: 8)

                              ],
                            ]).pOnly(bottom: 16),
                          ],

                          // series
                          if (!video.series.isEmptyOrNull) ...[
                            'Series:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${HelperDecensor.decensor(video.series)}'.text.underline.color(AppColor.muted).size(11).minFontSize(11).make().onInkTap(() async {
                              await _onItemSeriesClick(video);
                            }).pOnly(bottom: 16)
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
                            '${video.label}'.text.color(AppColor.muted).underline.size(11).minFontSize(11).make().pOnly(bottom: 16).onInkTap(() {
                              _onItemLabelClick(video);
                            }),
                          ],

                          // studio
                          if (!video.studio.isEmptyOrNull) ...[
                            'Studio:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.studio}'.text.color(AppColor.muted).underline.size(11).minFontSize(11).make().pOnly(bottom: 16).onInkTap(() {
                              _onItemStudioClick(video);
                            }),
                          ],

                          // director
                          if (!video.director.isEmptyOrNull) ...[
                            'Director:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.director}'.text.color(AppColor.muted).underline.size(11).minFontSize(11).make().pOnly(bottom: 16).onInkTap(() {
                              _onItemDirectorClick(video);
                            }),
                          ],



                          VStack([
                            // resolution
                            'Res:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.quality}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),

                            // filesize
                            'File Size:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                            '${video.filesize?.toFileSizeFormat()}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                          ]),

                          // ~~~
                          FutureBuilder(
                            future: _getMediaInfo(video.videoPath ?? ''),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null && snapshot.data!.length > 2) {
                                _mediaInfo.value = snapshot.data!;
                              }

                              return _mediaInfo.value.isNotEmpty
                                  ? VStack([
                                      // duration (non jav)
                                      if (video.duration == 0) ...[
                                        'Duration:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                                        '${_mediaInfo[3]}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),
                                      ],
                                    ])
                                  : 0.heightBox;
                            },
                          ),

                          // Path
                          'Path:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                          '${video.videoPath?.getLastSegments()}'.text.color(AppColor.muted).ellipsis.size(11).minFontSize(11).make().color(AppColor.hover).onInkTap(() async {
                            await _onItemVideoPathClick(video);
                          }).tooltip(video.videoPath ?? ''),

                          // added
                          'Added:'.tr.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4, top: 16),
                          '${video.createdAt?.reformatDate()}'.text.color(AppColor.muted).size(11).minFontSize(11).make().pOnly(bottom: 16),

                        ]).p12(),
                      ),
                    ).pSymmetric(h: 16).pOnly(bottom: 12),
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
        backgroundSettings: BackgroundSettings(blur: 5, color: Colors.transparent),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        actions: OverlayActions(onReady: () async => focusNode.requestFocus()),
        child: FocusScope(
          autofocus: true,
          child: KeyboardListener(
            focusNode: focusNode,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
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

                  ZStack([
                    Obx(
                      () => Zoom(
                        width: max(Get.width * 90 / 100, 400),
                        height: max(Get.height * 80 / 100, 400) - 80,
                        child: ExThumbnail(
                          imageUrl: '',
                          videoPath: video.videoPath,
                          width: max(Get.width * 90 / 100, 400),
                          height: max(Get.height * 80 / 100, 400) - 80,
                          fitMemory: BoxFit.contain,
                          position: idxSelectedNonJav.value,
                        ),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                        child: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: AppStyle.iconSize).p12(),
                      ).onInkTap(() => idxSelectedNonJav.value = idxSelectedNonJav.value + 10),
                    ).positioned(right: 8, top: 0, bottom: 0),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                        child: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: AppStyle.iconSize).p12(),
                      ).onInkTap(() => idxSelectedNonJav.value = idxSelectedNonJav.value - 10),
                    ).positioned(left: 8, top: 0, bottom: 0),

                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                        child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize).p8(),
                      ).onInkTap(() {
                        Overlayment.dismissLast();
                      }),
                    ).positioned(right: 8, top: 12, bottom: 0),
                  ]),

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
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                          child: '${idxSelectedJav.value + 1}/${video.screenshot!.length}'.text.size(11).minFontSize(11).make().p4(),
                        ),
                      ).p12(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: AppStyle.iconSize).p12(),
                        ).onInkTap(() {
                          if (idxSelectedJav.value < video.screenshot!.length - 1) {
                            idxSelectedJav.value++;
                          }
                        }),
                      ).positioned(right: 8, top: 0, bottom: 0),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: AppStyle.iconSize).p12(),
                        ).onInkTap(() {
                          if (idxSelectedJav.value > 0) {
                            idxSelectedJav.value--;
                          }
                        }),
                      ).positioned(left: 8, top: 0, bottom: 0),
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black180),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize).p8(),
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
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.actress?[index].nameRomaji == '' ? '${video.actress?[index].nameKana}' : '${video.actress?[index].nameRomaji}'}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kActress, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemCategoryClick(Videos video, int index) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.category?[index].category}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kCategory, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemSeriesClick(Videos video) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.series}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kSeries, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemLabelClick(Videos video) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.label}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kLabel, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemStudioClick(Videos video) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.studio}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kStudio, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemDirectorClick(Videos video) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final name = '${video.director}';
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kDirector, name, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<void> _onItemVideoPathClick(Videos video) async {
    final newTab = PageExploreController.isNewTabModifierPressed;
    final directory = p.dirname(video.videoPath ?? '');
    await Get.find<HomeController>().onMenuChange(kMenuExplore);
    final exploreC = Get.find<PageExploreController>();
    await exploreC.openSelection(kPath, directory, newTab: newTab);
    await Overlayment.dismissLast();
  }

  static Future<List<String>> _getMediaInfo(String path) async {
    final output = <String>[];
    await FFprobeKit.getMediaInformation(path).then((value) async {
      final medinfo = value.getMediaInformation();
      final stream = value.getMediaInformation()?.getStreams().first;
      output.add('${stream?.getWidth()}x${stream?.getHeight()}'); // -- [0] width x height
      output.add('${stream?.getHeight()}p'); // -- [1] resolution
      output.add('${int.parse(medinfo!.getSize()!).toFileSizeFormat()}'); // -- [2] file size
      output.add('${HelperMisc.durationFormatFFmpeg(num.parse(medinfo.getFormatProperties()!['duration'].toString()))}'); // -- [3] duration
    }).catchError((e) {
      AppLog.logW('PageSearchOverlay._getMediaInfo [$path] -> $e');
    });

    return output;
  }
}
