import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import 'page_download_controller.dart';

class PageDownloadView extends GetView<PageDownloadController> {
  const PageDownloadView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        HStack([
          Obx(
            () => CupertinoTextField(
              controller: controller.tecSearch,
              focusNode: controller.fnSearch,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: '${controller.phSearch}',
              style: TextStyle(color: Vx.white, fontSize: 14),
              prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
              suffix: HStack(
                [
                  // ** TODO
                ],
              ),
              onSubmitted: (s) {
                controller.currentPage.value = 1;
                controller.onSearch(s);
              },
            ).expand(),
          ),
          Obx(
            () => ZStack([
              IconButton(
                icon: Icon(
                  controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                  size: controller.filter.isFiltered.isTrue ? 16: 14,
                ),
                onPressed: () => controller.openDialogFilter(),
              ).pOnly(left: 8),

              controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox, 
            ]),
          ),
          IconButton(
            icon: Icon(UIconsPro.regularRounded.arrow_small_down, size: 18),
            onPressed: () => controller.openDownloadLog(),
          ).pOnly(left: 0),
          
        ]).pOnly(bottom: 12),

        // header
        HStack([
          Obx(() => 'Result : ${controller.totalResults}'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => 'Having: ${controller.havingVideos}'.text.size(10).minFontSize(10).bold.green400.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),

          Spacer(),
          Obx(() => 'Page: ${controller.currentPage}'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => 'Next: ${controller.hasNextPage.isTrue ? 'Yes' : 'No'}'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => '(${controller.videos.length})'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,

        ]),

        // list
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.search, size: 128),
                  title: controller.currentPage.value == 0 ? '~ Type Something ~' : 'No Data Found',
                  message: controller.currentPage.value == 0 ? 'you can type "Video Code" or "Title" to search' : 'No Result Found, as you searched for "${controller.tecSearch.text}"',
                ).expand()
              : modeWrapView().expand(),
        ),
        Obx(
          () => controller.downloadStdout.value.isNotEmpty
              ? HStack([
                  '${controller.downloadStdout}'.text.size(11).minFontSize(11).maxLines(1).make().expand(),
                  ExButtonText(
                    label: 'Cancel / Close',
                    labelSize: 12,
                    onPressed: () => controller.killProcessDownload(),
                  ),
                ]).pOnly(top: 12)
              : 0.heightBox,
        ),
      ],
    );
  }

  Widget modeWrapView() {
    return GridView.builder(
      controller: controller.scrollController,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.videos.length + (controller.isLoadingMore.isTrue ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= controller.videos.length) {
          return Container(
            color: AppColor.container,
            child: Center(
              child: CupertinoActivityIndicator(radius: 12),
            ),
          ).cornerRadius(8);
        }
        final item = controller.videos[i];
        return Container(
          color: AppColor.container,
          child: ZStack([
            ExThumbnail(
              imageUrl: item.fanArt ?? '',
              width: 300,
              height: 200,
              fitUrl: BoxFit.cover,
              withProxy: false,
            ).wh(300, 200),

            // ** match (already have )
            _buildOverlayContainer(
              color: Colors.green.withAlpha(100),
              isVisible: item.match == true,
            ),

            // ** is_released (false)
            _buildOverlayContainer(
              color: Colors.red.withAlpha(70),
              isVisible: item.isReleased == false,
            ),

            // ** has Clicked
            GetBuilder(
              init: HomeController(),
              builder: (controller) {
                return _buildOverlayContainer(
                  color: Colors.blue.withAlpha(100),
                  isVisible: item.isClicked == true,
                );
              },
            ),

            Container(
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                '${item.durationFormated?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).maxLines(1).ellipsis.make(),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(left: 0),

            Container(
              color: Vx.red500.withAlpha(140),
              width: 110,
              height: 18,
              child: VStack([
                'Uncensored Leak'.text.size(10).minFontSize(10).bold.maxLines(1).make().pSymmetric(h: 8),
              ]),
            ).positioned(right: 0, bottom: 62).hide(isVisible: item.isUncensoredLeak == true),

            // ** open trailer
            Icon(UIconsPro.regularRounded.play, size: 12)
                .wh(30, 30)
                .color(Vx.black)
                .cornerRadius(12)
                .onInkTap(() => HelperOpener.openTrailer(item))
                .positioned(right: 8, top: 4)
                .hide(isVisible: item.videoCode?.isValidVideoCode() ?? false),

            // ** open screenshot
            Icon(UIconsPro.regularRounded.picture, size: 12)
                .wh(30, 30)
                .color(Vx.black)
                .cornerRadius(12)
                .onInkTap(() => HelperOpener.openScreenshot(item))
                .positioned(right: 8, top: 36)
                .hide(isVisible: item.videoCode?.isValidVideoCode() ?? false),

            Container(
              color: AppColor.black180,
              width: 300,
              height: item.title != null && item.title != '' ? 63 : 33,
              child: VStack([
                '${item.videoCode}'.text.bold.size(12).ellipsis.make().onInkTap(() {
                  HelperMisc.copyToClipboard(item.videoCode, showToast: true);
                }),
                '${HelperDecensor.decensor(item.title ?? '')}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().w(240).hide(isVisible: item.title != null && item.title != ''),
              ]).p8(),
            ).positioned(bottom: 0, left: 0, right: 0),
          ]),
        ).cornerRadius(8).onInkTap(() {
          HelperOpener.openVideoInfo(item);
        });
      },
    );
  }

  Widget _buildOverlayContainer({required Color color, required bool isVisible}) {
    return Container(
      color: color,
      width: 300,
      height: 200,
    ).hide(isVisible: isVisible);
  }
}
