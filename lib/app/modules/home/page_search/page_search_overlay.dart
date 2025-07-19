import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../page_home/page_home_controller.dart';
import 'page_search_controller.dart';

mixin PageSearchOverlay {
  static Future<void> onItemTap(Videos video) async {
    final _controller = Get.find<PageSearchController>();
    final _mediaInfo = await _controller.getMediaInfo(video.videoPath ?? '');

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
            Container(
              width: double.infinity,
              height: 200,
              color: Vx.neutral900,
              child: video.fanArt.isBlank ?? true
                  ? FutureBuilder(
                      future: _controller.getThumbnail(video.videoPath ?? ''),
                      builder: (context, snapshot) {
                        return snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover, width: double.infinity) : 0.heightBox;
                      },
                    )
                  : CachedNetworkImage(
                      imageUrl: '${video.fanArt?.imgUrl()}',
                    ).onInkTap(() => _openScreenshot(video)),
            ),
            VStack(
              [
                '${video.videoCode.isNotEmptyAndNotNull ? video.videoCode : video.title.maxWords(3)}'.text.maxLines(2).align(TextAlign.center).bold.makeCentered().pSymmetric(v: 8),
                '${video.title}'.text.align(TextAlign.center).size(10).minFontSize(10).maxLines(3).ellipsis.makeCentered(),

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
                  constraints: BoxConstraints(minHeight: 100, maxHeight: 300),
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
                          '${video.actress?[i].nameRomaji}'.text.neutral300.underline.size(11).minFontSize(11).make().pOnly(right: 8),
                        ],
                      ]).pOnly(bottom: 16),
                    ],

                    // category
                    if (!video.category.isEmptyOrNull) ...[
                      'Category:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                      Wrap(children: [
                        for (int i = 0; i < video.category!.length; i++) ...[
                          '${video.category?[i].category}'.text.neutral300.underline.size(11).minFontSize(11).make().pOnly(right: 8),
                        ],
                      ]).pOnly(bottom: 16),
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

                    // series
                    if (!video.series.isEmptyOrNull) ...[
                      'Series:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                      '${video.series}'.text.neutral300.size(11).minFontSize(11).make().pOnly(bottom: 16),
                    ],

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

                    // Path
                    'Path:'.text.size(11).minFontSize(11).bold.make().pOnly(bottom: 4),
                    '${video.videoPath?.getLastSegments()}'.text.neutral300.ellipsis.size(11).minFontSize(11).make().color(Vx.neutral800).tooltip(video.videoPath ?? ''),
                  ]).p12().scrollVertical(),
                )
              ],
            ).pSymmetric(h: 16),
          ],
        ),
      ),
    );
  }

  static Future<void> _openScreenshot(Videos video) async {
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.topLeft,
        width: 400,
        height: double.infinity,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerLeft,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        child: VStack(
          [
            for (int i = 0; i < video.screenshot!.length; i++) ...[
              CachedNetworkImage(
                imageUrl: '${video.screenshot?[i].imgUrl()}',
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
                        child: CachedNetworkImage(
                          width: Get.width * 90 / 100,
                          height: Get.height * 90 / 100,
                          imageUrl: '${video.screenshot?[i].imgUrl()}',
                          fit: BoxFit.contain,
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
        ).scrollVertical(),
      ),
    );
  }

  // static Future<void> _openTrailer(Videos video) async {
  //   await Overlayment.show(
  //     context: Get.context,
  //     OverPanel(
  //       alignment: Alignment.topLeft,
  //       width: 400,
  //       height: double.infinity,
  //       animation: OverSlideAnimation(
  //         beginAlignment: Alignment.centerLeft,
  //         reverseDurationMilliseconds: 100,
  //         durationMilliseconds: 400,
  //       ),
  //       child: CachedNetworkImage(
  //         imageUrl: '${video.trailer?.imgUrl()}',
  //       ),
  //     ),
  //   );
  // }
}
