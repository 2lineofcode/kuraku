import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../core/app_color.dart';
import '../../../utils/helper_misc.dart';
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
        final item = controller.videos[index];
        if (item.poster == null || item.poster == '') {
          return Container(
            color: AppColor.container,
            child: FutureBuilder(
              future: controller.getThumbnail(item.videoPath ?? ''),
              builder: (context, snapshot) {
                // thumbanail -> failed
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return HStack([
                    Icon(CupertinoIcons.photo, size: 64).wh(180, 120).color(Vx.neutral900),
                    '${item.videoCode}'.text.size(12).bold.ellipsis.make().pSymmetric(h: 8).pOnly(right: 12),
                    '${item.title}'.text.size(11).minFontSize(11).ellipsis.make().pSymmetric(h: 8).pOnly(right: 12),
                    4.heightBox,
                  ]);
                }

                // thumbanail -> success
                return snapshot.hasData
                    ? Container(
                        color: AppColor.container,
                        child: HStack([
                          Image.memory(
                            snapshot.data!,
                            width: 180,
                            height: 120,
                            fit: BoxFit.fitHeight,
                          ).pOnly().color(Vx.neutral900).pOnly(right: 8),
                          VStack([
                            '${item.title.maxWords(1)}'.text.size(14).bold.ellipsis.make().pOnly(bottom: 8, right: 12),
                            '${item.title}'.text.size(11).maxLines(3).ellipsis.minFontSize(11).make().pOnly(bottom: 12, right: 12),
                            HStack([
                              Icon(CupertinoIcons.time, size: 12).pOnly(right: 4, top: 2),
                              '${item.duration}'.text.size(10).minFontSize(10).make(),
                              12.widthBox,
                              Icon(CupertinoIcons.calendar, size: 12).pOnly(right: 4, top: 2),
                              '${item.releaseDate}'.text.size(10).minFontSize(10).make(),
                              12.widthBox,
                              Icon(CupertinoIcons.circle, size: 12).pOnly(right: 4, top: 2),
                              '${item.label}'.text.size(10).minFontSize(10).make(),
                            ]),
                          ]).expand(),
                        ]),
                      ).wh(150, 120).cornerRadius(8)
                    : 0.heightBox;
              },
            ),
          ).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(item));
        } else {
          // fanart
          return Container(
            color: AppColor.container,
            child: HStack([
              CachedNetworkImage(
                imageUrl: '${item.fanArt?.imgUrl()}',
                width: 180,
                height: 120,
                fit: BoxFit.fitHeight,
              ).pOnly(right: 8),
              VStack([
                '${item.videoCode}'.text.size(14).bold.ellipsis.make().pOnly(bottom: 8, right: 12),
                '${item.title}'.text.size(11).maxLines(3).ellipsis.minFontSize(11).make().pOnly(bottom: 12, right: 12),
                HStack([
                  Icon(CupertinoIcons.time, size: 12).pOnly(right: 4, top: 2),
                  '${item.duration}'.text.size(10).minFontSize(10).make(),
                  12.widthBox,
                  Icon(CupertinoIcons.calendar, size: 12).pOnly(right: 4, top: 2),
                  '${item.releaseDate}'.text.size(10).minFontSize(10).make(),
                  12.widthBox,
                  Icon(CupertinoIcons.circle, size: 12).pOnly(right: 4, top: 2),
                  '${item.label}'.text.size(10).minFontSize(10).make(),
                ]),
              ]).expand(),
            ]),
          ).wh(150, 120).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(item));
        }
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
        final item = controller.videos[index];

        if (item.poster == null || item.poster == '') {
          return Container(
            color: AppColor.container,
            child: FutureBuilder(
              future: controller.getThumbnail(item.videoPath ?? ''),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: VStack([
                      Icon(CupertinoIcons.photo, size: 64).centered().color(Vx.neutral900).expand(),
                      '${item.title.maxWords(1)}'.text.size(12).bold.ellipsis.makeCentered().pSymmetric(h: 8),
                      '${item.title}'.text.size(11).minFontSize(11).ellipsis.makeCentered().pSymmetric(h: 8),
                      4.heightBox,
                    ]).onInkTap(() => PageSearchOverlay.onItemTap(item)),
                  );
                }

                return snapshot.hasData
                    ? VStack([
                        Image.memory(snapshot.data!, fit: BoxFit.cover, width: double.infinity).expand(),
                        4.heightBox,
                        '${item.title.maxWords(1)}'.text.size(12).bold.ellipsis.makeCentered().pSymmetric(h: 8),
                        '${item.title}'.text.size(11).minFontSize(11).ellipsis.makeCentered().pSymmetric(h: 8),
                        4.heightBox,
                      ]).onInkTap(() => PageSearchOverlay.onItemTap(item))
                    : 0.heightBox;
              },
            ),
          ).cornerRadius(8);
        } else {
          return Container(
            color: AppColor.container,
            child: VStack([
              CachedNetworkImage(
                imageUrl: '${item.poster?.imgUrl()}',
                fit: BoxFit.fill,
              ).expand(),
              4.heightBox,
              '${item.videoCode}'.text.size(12).bold.ellipsis.makeCentered().pSymmetric(h: 8),
              '${item.title}'.text.size(11).minFontSize(11).ellipsis.makeCentered().pSymmetric(h: 8),
              4.heightBox,
            ]),
          ).cornerRadius(8).onInkTap(() => PageSearchOverlay.onItemTap(item));
        }
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
