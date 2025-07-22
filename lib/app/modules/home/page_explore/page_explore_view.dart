import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../utils/helper_misc.dart';
import '../../widgets/widget_thumbnail.dart';
import 'page_explore_controller.dart';

class PageExploreView extends GetView<PageExploreController> {
  const PageExploreView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        // Filter By
        'Filter By'.text.size(12).make().pOnly(bottom: 16),
        ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: controller.filterType.length,
          itemBuilder: (context, index) {
            return Obx(
              () => ExButtonOutline(
                label: controller.filterType[index],
                labelSize: 12,
                labelColor: controller.filterTypeSelected.value == controller.filterType[index] ? Vx.white : Vx.neutral600,
                borderColor: controller.filterTypeSelected.value == controller.filterType[index] ? Vx.white : Vx.neutral600,
                onPressed: () => controller.onFilterByChange(controller.filterType[index]),
              ).pOnly(right: 8),
            );
          },
        ).wh(double.infinity, 30),

        24.heightBox,
        HStack(
          [
            Container(
              width: 200,
              height: double.infinity,
              color: Colors.transparent,
              child: VStack(
                [
                  Obx(
                    () => CupertinoTextField(
                      controller: controller.tecSearch,
                      focusNode: controller.fnSearch,
                      placeholder: controller.phSearchText.value,
                      style: TextStyle(color: Vx.white, fontSize: 12),
                      clearButtonMode: OverlayVisibilityMode.editing,
                      onChanged: (s) => controller.onOListSearch(s),
                    ).pSymmetric(v: 8),
                  ),
                  Obx(
                    () => controller.oListFiltered.isEmpty
                        ? ExUiErrorOrEmpty(
                            illustration: Icon(CupertinoIcons.lab_flask_solid, size: 32),
                            title: 'No Data Found',
                            message: 'No Result Found, as you searched for "${controller.tecSearch.text}"',
                          ).expand()
                        : ListView.separated(
                            itemCount: controller.oListFiltered.length,
                            separatorBuilder: (context, index) => Divider(),
                            itemBuilder: (context, index) {
                              final item = controller.oListFiltered[index];
                              return Obx(
                                () => InkWell(
                                  onTap: () => controller.onOListTap(item),
                                  child: HStack([
                                    // image
                                    if (controller.filterTypeSelected.value == kActress) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(90),
                                        child: CachedNetworkImage(imageUrl: '${Env.actressAvatarBaseUrl}/${item.imgUrl}', width: 48, height: 48, fit: BoxFit.cover),
                                      ),
                                    ],

                                    // path only
                                    if (controller.filterTypeSelected.value == kPath) ...[
                                      if (item.name!.contains('/Users')) ...[
                                        'Local → ${item.name!.getLastPath()} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ] else ...[
                                        'External → ${item.name!.getLastSegments(segment: 1)} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ],
                                    ]
                                    // other ~
                                    else ...[
                                      FutureBuilder(
                                          future: HelperMisc.decensor(item.name),
                                          builder: (context, snapshot) {
                                            return snapshot.hasData ? '${snapshot.data} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand() : 0.heightBox;
                                          }),
                                    ],
                                  ]).color(item == controller.oListSelected.value ? AppColor.selected : Colors.transparent).cornerRadius(8),
                                ),
                              );
                            },
                          ).pOnly(left: 8, top: 8).expand(),
                  ),
                ],
              ),
            ),
            Container(height: double.infinity, color: AppColor.container).w(1).pSymmetric(h: 8),

            // ~
            Container(
              height: double.infinity,
              color: Colors.transparent,
              child: VStack([
                Obx(() => buildHeader()),
                Obx(
                  () => controller.vList.isEmpty
                      ? ExUiErrorOrEmpty(
                          illustration: Icon(
                          CupertinoIcons.chevron_left_2,
                          size: 32,
                        )).expand()
                      : controller.vListViewMode.value == kLocal
                          ? vListLocal().expand()
                          : vListR18().expand(),
                ),
              ]),
            ).expand(),
          ],
        ).expand(),
      ],
    );
  }

  Widget buildHeader() {
    if (controller.vList.isEmpty) return Container();

    return Container(
      width: double.infinity,
      height: 50,
      decoration: ExDecorator.box(borderColor: AppColor.border),
      child: Obx(
        () => Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.oListSelected.value.imgUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(90),
                child: CachedNetworkImage(imageUrl: '${Env.actressAvatarBaseUrl}/${controller.oListSelected.value.imgUrl}', width: 32, height: 32, fit: BoxFit.cover),
              ).centered().pOnly(right: 12),
            ] else ...[
              ExAvatarView(
                source: '',
                name: controller.oListSelected.value.name ?? '',
                size: 32,
                bgColor: AppColor.selected,
                textSize: 12,
              ).centered().pOnly(right: 12),
            ],
            VStack([
              '${controller.oListSelected.value.name!.trim()}'.text.bold.size(12).ellipsis.make().pOnly(top: 6, bottom: 4),
              Obx(
                () => HStack([
                  'Local: ${controller.oListSelected.value.count}'
                      .text
                      .size(10)
                      .minFontSize(10)
                      .maxLines(1)
                      .make()
                      .pOnly(left: 12, right: 12)
                      .color(controller.vListViewMode.value == kLocal ? AppColor.selected : AppColor.unselected)
                      .cornerRadius(8)
                      .onInkTap(() async => await controller.onHeaderLocalTap())
                      .pOnly(right: 12),
                  'R18: ${controller.r18TotalVideo}'
                      .text
                      .size(10)
                      .minFontSize(10)
                      .maxLines(1)
                      .make()
                      .pOnly(left: 12, right: 12)
                      .color(controller.vListViewMode.value == kR18 ? AppColor.selected : AppColor.unselected)
                      .cornerRadius(8)
                      .pOnly(right: 12)
                      .onInkTap(() async => await controller.onHeaderR18Tap())
                      .pOnly(right: 12).hide(isVisible: controller.r18TotalVideo.value != 0),
                ]),
              ),
            ]).expand(),
          ],
        ).pSymmetric(h: 8),
      ),
    ).pOnly(bottom: 12);
  }

  Widget vListLocal() {
    return Wrap(
      spacing: 8,
      runSpacing: 12,
      children: [
        for (int i = 0; i < controller.vList.length; i++) ...[
          Container(
            color: AppColor.container,
            child: ZStack([
              ExThumbnailV(
                imageUrl: controller.vList[i].poster,
                videoPath: controller.vList[i].videoPath,
                width: 140,
                height: 200,
              ).wh(140, 200),
              Container(
                color: Vx.black.withAlpha(150),
                width: 140,
                height: 20,
                child: '${controller.vList[i].videoCode == '' ? controller.vList[i].title?.maxChars(10) : controller.vList[i].videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
              ).positioned(bottom: 0),
            ]),
          ).cornerRadius(8).onInkTap(() => controller.onVListTap(controller.vList[i])),
        ]
      ],
    ).scrollVertical();
  }

  Widget vListR18() {
    return ListView.builder(
      itemCount: controller.r18ListVideo.length,
      itemBuilder: (context, i) {
        return ZStack([
          ExThumbnailV(
            imageUrl: controller.r18ListVideo[i]['fan_art'] ?? '',
            videoPath: '',
            width: 270,
            height: 200,
          ).wh(270, 200).cornerRadius(8),
          Container(
            color: Vx.black.withAlpha(150),
            width: 270,
            height: 20,
            child: '${controller.r18ListVideo[i]['video_code']}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0),
          Container(
            color: Vx.black.withAlpha(150),
            width: 70,
            height: 18,
            child: '${controller.r18ListVideo[i]['release_date']}'.text.size(9).minFontSize(9).align(TextAlign.center).ellipsis.makeCentered(),
          ).positioned(right: 0),
        ]).onInkTap(() async {
          await launchUrlString('https://njavtv.com/en/${controller.r18ListVideo[i]['video_code']}');
        }).pOnly(bottom: 12);
      },
    );
  }
}
