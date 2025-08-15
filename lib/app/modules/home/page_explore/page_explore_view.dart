import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
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
                labelColor: controller.filterTypeSelected.value == controller.filterType[index] ? Vx.white : Vx.neutral500,
                borderColor: controller.filterTypeSelected.value == controller.filterType[index] ? AppColor.selected : AppColor.container,
                backgroundColor: controller.filterTypeSelected.value == controller.filterType[index] ? AppColor.selected : AppColor.container,
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
                        ? uiNoData().expand()
                        : ListView.separated(
                            itemCount: controller.oListFiltered.length,
                            separatorBuilder: (context, index) => Divider(color: AppColor.border),
                            itemBuilder: (context, index) {
                              final item = controller.oListFiltered[index];
                              return Obx(
                                () => InkWell(
                                  onTap: () => controller.onOListTap(item),
                                  child: HStack([
                                    // image
                                    if (controller.filterTypeSelected.value == kActress) ...[
                                      item.imgUrl?.trim() != ''
                                          ? ExThumbnail(
                                              imageUrl: '${Env.actressUrl}/${item.imgUrl}',
                                              width: 48,
                                              height: 48,
                                              fitUrl: BoxFit.cover,
                                              withProxy: false,
                                            ).cornerRadius(90)
                                          : ExAvatarView(
                                              source: '',
                                              height: 48,
                                              width: 48,
                                              name: item.name,
                                            ),
                                    ],

                                    // path only
                                    if (controller.filterTypeSelected.value == kPath) ...[
                                      if (item.name!.contains('/Volumes')) ...[
                                        'External → ${item.name!.getLastSegments(segment: 1)} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ] else ...[
                                        'Local → ${item.name!.getLastPath()} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ],
                                    ]
                                    // other ~
                                    else ...[
                                      '${item.name} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand()
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
                        ).pOnly(bottom: 12),
                        message: 'Please select left area first',
                        
                        ).expand()
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

  Widget uiNoData() {
    return ExUiErrorOrEmpty(
      illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
      title: 'No Data Found',
      message: 'No Result Found, as you searched for "${controller.tecSearch.text}"',
    );
  }

  Widget buildHeader() {
    if (controller.vList.isEmpty) return Container();
    final item = controller.oListSelected.value;
    return Container(
      width: double.infinity,
      height: 50,
      decoration: ExDecorator.box(borderColor: AppColor.border),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imgUrl != null) ...[
            item.imgUrl?.trim() == ''
                ? ExAvatarView(source: '', name: item.name, size: 32).pOnly(right: 12)
                : ExThumbnail(
                    imageUrl: '${Env.actressUrl}/${item.imgUrl}',
                    width: 32,
                    height: 32,
                    fitUrl: BoxFit.cover,
                    withProxy: false,
                  ).cornerRadius(90).centered().pOnly(right: 12),
          ] else ...[
            ExAvatarView(
              source: '',
              name: item.name ?? '',
              size: 32,
              bgColor: AppColor.selected,
              textSize: 12,
            ).centered().pOnly(right: 12),
          ],
          VStack([
            FutureBuilder(
              future: HelperMisc.decensor(item.name!.trim()),
              builder: (context, snapshot) {
                return snapshot.hasData
                    ? '${KanaKit().isKana(snapshot.data ?? '') ? KanaKit().toRomaji(snapshot.data ?? '') : snapshot.data}'.text.bold.size(12).ellipsis.make().pOnly(top: 6, bottom: 4)
                    : 0.heightBox;
              },
            ),
            Obx(
              () => HStack([
                'Local: ${item.count}'
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
                    .pOnly(right: 12)
                    .hide(isVisible: controller.r18TotalVideo.value != 0),
              ]),
            ),
          ]).expand(),
        ],
      ).pSymmetric(h: 8),
    ).pOnly(bottom: 12);
  }

  Widget vListLocal() {
    return GridView.builder(
      padding: EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 140 / 200,
      ),
      itemCount: controller.vList.length,
      itemBuilder: (context, i) {
        final item = controller.vList[i];
        return RepaintBoundary(
          child: Container(
            color: AppColor.container,
            child: ZStack([
              ExThumbnail(
                imageUrl: item.fanArt,
                videoPath: item.videoPath,
                width: 140,
                height: 200,
                prefix: 2.15,
              ).wh(140, 200),
              Container(
                color: Vx.black.withAlpha(150),
                width: 140,
                height: 20,
                child: '${item.videoCode == '' ? item.title?.maxChars(10) : item.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
              ).positioned(bottom: 0),
            ]),
          ).cornerRadius(8).onInkTap(() => controller.onVListTap(item)),
        );
      },
    );
  }

  Widget vListR18() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.r18ListVideo.length,
      itemBuilder: (context, i) {
        final item = controller.r18ListVideo[i];
        return ZStack(
          [
            ExThumbnail(
              imageUrl: item['fan_art'] ?? '',
              width: 300,
              height: 200,
            ).wh(300, 200).cornerRadius(8),

            // ** match (already have )
            Container(
              color: Colors.green.withAlpha(100),
              width: 300,
              height: 200,
            ).hide(isVisible: item['match'] == true),

            // ** has Clicked
            GetBuilder(
              init: PageExploreController(),
              builder: (controller) {
                return Container(
                  color: Colors.blue.withAlpha(100),
                  width: 300,
                  height: 200,
                ).hide(isVisible: item['is_clicked'] == true);
              },
            ),

            Container(
              color: Vx.black.withAlpha(150),
              width: 300,
              height: 20,
              child: '${item['video_code']}'.text.bold.ellipsis.make().pOnly(left: 8),
            ).onInkTap(() async {
              HelperMisc.copyToClipboard(item['video_code'], showToast: true);
            }).positioned(bottom: 0),

            Container(
              color: Vx.black.withAlpha(150),
              width: 70,
              height: 18,
              child: '${item['release_date']}'.text.size(9).minFontSize(9).align(TextAlign.center).ellipsis.makeCentered(),
            ).positioned(left: 0),

            // ** open trailer
            Icon(UIconsPro.regularRounded.play, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
              HelperOpener.openTrailer(item);
            }).positioned(right: 8, top: 4),

            // ** open screenshot
            Icon(UIconsPro.regularRounded.picture, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
              HelperOpener.openScreenshot(item);
            }).positioned(right: 8, top: 36),

          ],
        ).onInkTap(() async => await HelperOpener.openVideoInfo(item)).pOnly(bottom: 12);
      },
    );
  }
}
