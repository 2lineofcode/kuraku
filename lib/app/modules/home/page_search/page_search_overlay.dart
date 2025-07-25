import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
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
                  HelperMisc.copyToClipboard(video.videoCode ?? '');
                  HelperToast.info('${video.videoCode} Copied to clipboard');
                }).pSymmetric(v: 8),
                '${video.title}'.text.align(TextAlign.center).size(10).minFontSize(10).maxLines(3).ellipsis.makeCentered().tooltip(video.videoPath?.getFileName().noExt() ?? ''),

                ExDivider().pSymmetric(v: 16),

                // action
                HStack(
                  [
                    Spacer(),
                    // play
                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: IconButton(
                        icon: Icon(CupertinoIcons.play, size: 16),
                        onPressed: () => {
                          Overlayment.dismissLast(),
                          HelperOpener.openFile(video),
                        },
                      ),
                    ).pOnly(right: 8),

                    // add to favorite
                    GetBuilder<PageSearchController>(
                      init: _controller,
                      builder: (b) => Container(
                        decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                        child: IconButton(
                          icon: video.isFavorite == 1 ? Icon(CupertinoIcons.star_fill, size: 16, color: Vx.orange500) : Icon(CupertinoIcons.star, size: 16, color: null),
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
                              icon: Icon(CupertinoIcons.refresh, size: 16),
                              onPressed: () => _controller.renewMetadata(video),
                            ),
                          ).pOnly(right: 8)
                        : 0.heightBox,

                    Container(
                      decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                      child: IconButton(
                        icon: Icon(CupertinoIcons.folder, size: 16),
                        onPressed: () => HelperOpener.openFolderFromFile(video.videoPath ?? ''),
                      ),
                    ).pOnly(right: 8),

                    Spacer(),
                  ],
                ).pOnly(bottom: 16),

                // metadata
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: 100, maxHeight: 268),
                  decoration: ExDecorator.box(borderRadius: 4, borderColor: AppColor.border, borderWidth: 1),
                  child: VStack([
                    HStack([
                      Icon(CupertinoIcons.chevron_left_slash_chevron_right, size: 16).pOnly(right: 8),
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
                  ]).p12().scrollVertical(),
                )
              ],
            ).pSymmetric(h: 16),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~
  // ────────────────────────────────────────────────────────────────
  static Future<void> _openScreenshot(Videos video) async {
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.topLeft,
        width: video.screenshot.isEmptyOrNull ? Get.width * 90 / 100 : 400,
        height: double.infinity,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerLeft,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        child: VStack(
          [
            if (video.screenshot.isEmptyOrNull) ...[
              ExThumbnail(
                imageUrl: '',
                videoPath: video.videoPath,
                width: video.screenshot.isEmptyOrNull ? Get.width * 90 / 100 : 400,
                height: Get.height,
                fitMemory: BoxFit.fitHeight,
              ),
            ] else ...[
              for (int i = 0; i < video.screenshot!.length; i++) ...[
                ExThumbnail(
                  imageUrl: '${video.screenshot?[i]}',
                  width: video.screenshot.isEmptyOrNull ? Get.width * 90 / 100 : 400,
                  height: 300,
                  fitUrl: BoxFit.cover,
                ).onInkTap(() {
                  Overlayment.show(
                    context: Get.context,
                    OverPanel(
                      alignment: Alignment.center,
                      width: Get.width * 90 / 100,
                      height: Get.height * 90 / 100,
                      child: ZStack([
                        Zoom(
                          width: Get.width * 90 / 100,
                          height: Get.height * 90 / 100,
                          child: ExThumbnail(
                            imageUrl: '${video.screenshot?[i]}',
                            width: Get.width * 90 / 100,
                            height: Get.height * 90 / 100,
                            fitUrl: BoxFit.contain,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Overlayment.dismissLast(),
                          icon: Icon(CupertinoIcons.clear),
                        ).positioned(right: 16, top: 24),
                      ]),
                    ),
                  );
                }),
              ],
            ],
          ],
        ).scrollVertical(),
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
    ExLoading.show(paddingSymmetric: 240);
    await FFprobeKit.getMediaInformation(path).then((value) async {
      ExLoading.dismiss();
      final medinfo = value.getMediaInformation();
      final stream = value.getMediaInformation()?.getStreams().first;
      output.add('${stream?.getWidth()}x${stream?.getHeight()}'); // -- [0] width x height
      output.add('${stream?.getHeight()}p'); // -- [1] resolution
      output.add('${int.parse(medinfo!.getSize()!).toFileSize()}'); // -- [2] file size
      output.add('${HelperMisc.durationFormat2(num.parse(medinfo.getFormatProperties()!['duration'].toString()))}'); // -- [3] duration
    }).catchError((e) {
      ExLoading.dismiss();
      HelperToast.error('Could not get media info, please check file path, $path');
    });

    return output;
  }
}
