import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../widgets/widget_thumbnail.dart';
import 'page_search_controller.dart';
import 'page_search_overlay.dart';

class PageSearchView extends GetView<PageSearchController> {
  const PageSearchView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        HStack([
          CupertinoTextField(
            controller: controller.tecSearch,
            focusNode: controller.fnSearch,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: '${controller.phSearch}',
            style: TextStyle(color: Vx.white, fontSize: 14),
            onSubmitted: (value) {
              controller.onSearch();
            },
          ).expand(),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.regularRounded.apps, size: 14, color: controller.viewModeSelected.value == 'grid' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = kGrid,
            ),
          ),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.regularRounded.list_timeline, size: 14, color: controller.viewModeSelected.value == 'list' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = kList,
            ),
          ),
        ]).pOnly(bottom: 24),
        Obx(
          () => controller.isSearchMode.isTrue ? 'Result: ${controller.videos.length} Videos'.text.size(12).make().pOnly(bottom: 16) : 0.heightBox,
        ),
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
                  title: 'No Data Found',
                  message: 'No Result Found, as you searched for "${controller.tecSearch.text}"\nor Add some video to your library first.',
                ).expand()
              : controller.viewModeSelected.value == kGrid
                  ? modeGridView().expand()
                  : modeListView().expand(),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ seperate
  // ────────────────────────────────────────────────────────────────
  Widget modeListView() {
    return ListView.separated(
      itemCount: controller.videos.length,
      separatorBuilder: (context, index) => 12.heightBox,
      itemBuilder: (context, index) {
        final video = controller.videos[index];
        return Container(
          color: AppColor.container,
          child: HStack(
            crossAlignment: CrossAxisAlignment.start,
            alignment: MainAxisAlignment.start,
            [
              ExThumbnail(
                imageUrl: video.fanArt,
                videoPath: video.videoPath,
                width: 200,
                height: 120,
                fitUrl: BoxFit.cover,
              ).pOnly(right: 12),
              VStack([
                '${video.videoCode == '' ? video.title?.maxWords(5) : video.videoCode}'.text.bold.ellipsis.make().pSymmetric(v: 8),
                '${video.title}'.text.xs.maxLines(3).ellipsis.make(),
                Spacer(),
                HStack([
                  if (video.releaseDate != '') ...[
                    Icon(UIconsPro.regularRounded.calendar_minus, size: 10).pOnly(right: 6),
                    '${video.releaseDateFormated}'.text.size(10).minFontSize(10).make().pOnly(right: 12),
                  ],
                  if (video.series != '') ...[
                    Icon(UIconsPro.regularRounded.tags, size: 10, color: Vx.purple200).pOnly(right: 6),
                    '${video.series}'.text.size(10).purple200.maxLines(1).ellipsis.minFontSize(10).make().pOnly(right: 12).expand(),
                  ],
                ]).pOnly(bottom: 8),
              ]).pOnly(right: 12).expand(),
            ],
          ),
        ).wh(200, 120).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(video));
      },
    );
  }

  Widget modeGridView() {
    return GridView.builder(
      controller: controller.scrollController,
      padding: EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 120 / 200,
      ),
      itemCount: controller.videos.length,
      itemBuilder: (context, i) {
        final item = controller.videos[i];
        return RepaintBoundary(
          child: Container(
            color: AppColor.container,
            child: ZStack([
              ExThumbnail(
                imageUrl: item.fanArt,
                videoPath: item.videoPath,
                width: 120,
                height: 200,
                prefix: 2.5,
              ).wh(120, 200),
              Container(
                color: Vx.black.withAlpha(150),
                width: 120,
                height: 20,
                child: '${item.videoCode == '' ? item.title?.maxChars(10) : item.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
              ).positioned(bottom: 0),
            ]),
          ).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(item)),
        );
      },
    );
  }
}
