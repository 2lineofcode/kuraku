import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

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
            placeholder: 'EYAN-181',
            style: TextStyle(color: Vx.white, fontSize: 14),
            onSubmitted: (value) {
              controller.onSearch();
            },
          ).expand(),
          Obx(
            () => IconButton(
              icon: Icon(CupertinoIcons.square_grid_3x2, size: 18, color: controller.viewModeSelected.value == 'grid' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = 'grid',
            ),
          ),
          Obx(
            () => IconButton(
              icon: Icon(CupertinoIcons.list_dash, size: 18, color: controller.viewModeSelected.value == 'list' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = 'list',
            ),
          ),
        ]).pOnly(bottom: 24),
        Obx(() => 'Result: ${controller.videos.length} Videos'.text.size(12).make().pOnly(bottom: 16)),
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(CupertinoIcons.lab_flask_solid, size: 32),
                  title: 'No Data Found',
                  message: 'No Result Found, as you searched for "${controller.tecSearch.text}"\nor Add some video to your library first.',
                ).expand()
              : controller.viewModeSelected.value == 'grid'
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
              ExThumbnailV(
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
                    Icon(CupertinoIcons.calendar, size: 12).pOnly(right: 4),
                    '${video.releaseDateFormated}'.text.size(11).minFontSize(11).make().pOnly(right: 12),
                  ],

                  if (video.releaseDate != '') ...[
                    Icon(CupertinoIcons.circle, size: 12).pOnly(right: 4),
                    '${video.label}'.text.size(11).minFontSize(11).make().pOnly(right: 12),
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
      itemCount: controller.videos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.55,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final video = controller.videos[index];
        return Container(
          color: AppColor.container,
          child: ZStack([
            ExThumbnailV(
              imageUrl: video.poster,
              videoPath: video.videoPath,
              width: 120,
              height: 200,
            ),
            Container(
              color: Vx.black.withAlpha(150),
              height: 20,
              width: 120,
              child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
            ).positioned(bottom: 0),
          ]),
        ).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(video));
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────
// ⵌ ~~~
// ────────────────────────────────────────────────────────────────
class OverlayExample extends StatelessWidget {
  const OverlayExample({
    super.key,
    required this.title,
    this.currentUrl,
  });
  final String title;
  final String? currentUrl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: HStack([
        '$title'.text.make(),
        Spacer(),
        CloseButton(),
      ]).p64(),
    );
  }
}
