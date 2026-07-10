import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_panel/home_panel_video_info.dart';
import 'page_search_controller.dart';

class PageSearchView extends GetView<PageSearchController> {
  const PageSearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => controller.isFresh.isFalse
          ? buildPage()
          : ExUiErrorOrEmpty(
              illustration: Icon(UIconsPro.regularRounded.square_dashed_circle_plus, size: 128),
              title: '~ Fresh ~',
              message: 'Hi There, Select Or Drag & Drop your JAV Folder Here',
            ),
    );
  }

  Widget buildPage() {
    return VStack(
      [
        HStack([

          // search
          CupertinoTextField(
            controller: controller.tecSearch,
            focusNode: controller.fnSearch,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: '${controller.phSearch.value}',
            style: TextStyle(color: Vx.white, fontSize: 14),
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            suffix: 
            0.heightBox,
            onSubmitted: (value) => controller.onSearch(),
          ).expand(),

          Obx(
            () => IconButton(
              tooltip: controller.isSemanticMode.value ? 'AI Search On' : 'AI Search Off',
              onPressed: controller.toggleSemanticMode,
              icon: controller.isSemanticBusy.value
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : Icon(
                      controller.isSemanticMode.value
                          ? UIconsPro.boldRounded.sparkles
                          : UIconsPro.regularRounded.sparkles,
                      size: controller.isSemanticMode.value ? 16 : 14,
                      color: controller.isSemanticMode.value ? Vx.amber300 : null,
                    ),
            ).pOnly(left: 4),
          ),

          // filter
          Obx(
            () => ZStack([
              IconButton(
                icon: Icon(
                  controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                  size: controller.filter.isFiltered.isTrue ? 16 : 14,
                ),
                onPressed: () => controller.openDialogFilter(),
              ).pOnly(left: 8),
              controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
            ]),
          ),

          // sort by
          CustomPopup(
            content: VStack([
              'Sort By:'.text.bold.black.make(),
              Divider(),
              ExButtonText(
                label: controller.sortBy.value == 'Random' ? '◉ Random' : '◎ Random',
                labelSize: 13,
                labelColor: Vx.black,
                onPressed: () => {controller.onSortByChange('Random'), Get.back()},
              ).pOnly(right: 6),
              ExButtonText(
                label: controller.sortBy.value == 'Release Date' ? '◉ Release Date' : '◎ Release Date',
                labelSize: 13,
                labelColor: Vx.black,
                onPressed: () => {controller.onSortByChange('Release Date'), Get.back()},
              ),
              ExButtonText(
                label: controller.sortBy.value == 'View Count' ? '◉ View Count' : '◎ View Count',
                labelSize: 13,
                labelColor: Vx.black,
                onPressed: () => {controller.onSortByChange('View Count'), Get.back()},
              ),
              ExButtonText(
                label: controller.sortBy.value == 'File Size' ? '◉ File Size' : '◎ File Size',
                labelSize: 13,
                labelColor: Vx.black,
                onPressed: () => {controller.onSortByChange('File Size'), Get.back()},
              ),
            ]).w(150),
            child: Container(
              decoration: ExDecorator.box(fillColor: AppColor.selected.withAlpha(150), borderColor: Colors.transparent, borderRadius: 4),
              child: HStack([
                Icon(UIconsPro.regularRounded.sort, size: 12),
                '${controller.sortBy}'.text.size(11).minFontSize(11).make().pOnly(left: 4),
              ]).p(7),
            ),
          ).pOnly(left: 8,right: 12),

          
        ]).pOnly(bottom: 24),


        Obx(() => controller.isSearchMode.isTrue
            ? HStack(
                [
                  '${controller.semanticResultLabel.value.isEmpty ? 'Result' : controller.semanticResultLabel.value}: ${controller.videos.length} Videos'.text.size(12).make(),
                  Spacer(),
                  if (controller.videos.isNotEmpty) ...[
                    'PLAY ALL'.text.underline.size(12).make().pOnly(right: 16).onInkTap(() {
                      HelperOpener.openVideoFile(controller.videos.first, playlist: controller.videos);
                    }),
                  ],
                ],
              ).pOnly(bottom: 16)
            : 0.heightBox),
        
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
                  title: 'No Data Found',
                  message: 'No Result Found, as you searched for "${controller.tecSearch.text}"\nor Add some video to your library first.',
                ).expand()
              : modeGridView().expand(),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget modeGridView() {
    double width = 150;
    double height = 230;

    return GridView.builder(
      controller: controller.scrollGridController,
      padding: EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: width,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: width / height,
      ),
      itemCount: controller.videos.length,
      itemBuilder: (context, i) {
        final item = controller.videos[i];
        return RepaintBoundary(
          child: buildLayoutPoster(item, width, height),
        );
      },
    );
  }



  Widget buildLayoutPoster(
    Videos video,
    double width,
    double height, {
    showReleaseDate = true,
    showViewCount = true,
    showQuality = true,
  }) {
    return DoubleTap(
      onSingleTap: () async => await HomePanelVideoInfo.open(video),
      onDoubleTap: () async => await HelperOpener.openVideoFile(video),
      child: Container(
        color: AppColor.container,
        child: ZStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            videoPath: video.videoPath,
            width: width,
            height: height,
            prefix: 2.3,
            fitUrl: BoxFit.fitWidth,
            quickPreview: true,
            previewTitle: video.videoCode?.isNotEmpty == true ? video.videoCode : video.title,
            previewSubtitle: (video.actress ?? []).map((item) => item.nameRomaji ?? '').where((item) => item.isNotEmpty).join(', '),
            previewScreenshots: video.screenshot,
            previewDurationSeconds: (video.duration ?? 0).toInt() * 60,
          ),

          // sub id?
          if (video.videoPath?.isHasIdSub() == true) ...[
            Container(
              color: Vx.blue600.withAlpha(200),
              child: HStack([
                '🇮🇩'.text.size(10).minFontSize(10).make().tooltip('ID Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

           // sub en?
          if (video.videoPath?.isHasEnSub() == true) ...[
            Container(
              color: Vx.purple600.withAlpha(200),
              child: HStack([
                '🇬🇧'.text.size(10).minFontSize(10).make().tooltip('EN Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // reduce mosaic?
          if (video.videoPath?.isHasUncensored() == true) ...[
            Container(
              color: Vx.red600.withAlpha(200),
              child: HStack([
                '🎞️'.text.size(10).minFontSize(10).make().tooltip('Reduce Mosaic'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // Release date
          if (showReleaseDate) ...[
            Container(
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                video.releaseDate.isNotEmptyAndNotNull
                    ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}')
                    : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: ${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}')
              ]).p4(),
            ).cornerRadius(8).p2(),
          ],

          // Quality
          if (video.quality.isNotEmptyAndNotNull) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                '${HelperMisc.formatVideoQuality(video.quality ?? '').maxWords(1)}'.text.orange500.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.filesize?.toFileSizeFormat() != null ? '${video.filesize?.toFileSizeFormat()}' : '').positioned(bottom: 24, left: 4)
          ],

          if (controller.semanticScoreByVideoId[(video.id ?? '').trim()] != null) ...[
            Container(
              color: Vx.amber700.withAlpha(220),
              child: HStack([
                'AI ${(controller.semanticScoreByVideoId[(video.id ?? '').trim()]! * 100).toStringAsFixed(0)}%'.text.black.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).positioned(bottom: 24, right: 4),
          ],

          // View count
          if (showViewCount) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                Icon(UIconsPro.solidRounded.eye, size: 10).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: ${video.viewCount}' : '').positioned(bottom: 46, right: 4),
          ],

           // Video title
          Container(
            color: AppColor.black180,
            height: 20,
            width: width,
            child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0, left: 0, right: 0),
        ]),
      ).cornerRadius(8).pOnly(right: 8),
    );
  }

}
