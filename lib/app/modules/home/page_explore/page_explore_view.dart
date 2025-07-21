import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../core/app_color.dart';
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
                              final bu = 'https://next-javit-api.vercel.app/api?image=https://pics.dmm.co.jp/mono/actjpgs/';
                              final item = controller.oListFiltered[index];
                              return Obx(
                                () => InkWell(
                                  onTap: () => controller.onOListTap(item),
                                  child: HStack([
                                    // image
                                    if (!'$bu${item.imgUrl}'.contains('null') && controller.filterTypeSelected.value == 'Actress') ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(90),
                                        child: Image.network('$bu${item.imgUrl}', width: 48, height: 48, fit: BoxFit.cover),
                                      ),
                                    ],
                                    // name
                                    '${item.name} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                  ]).color(item == controller.oListSelected.value ? AppColor.selected : Colors.transparent),
                                ),
                              );
                            },
                          ).pOnly(left: 8, top: 8).expand(),
                  ),
                ],
              ),
            ),
            Container(height: double.infinity, color: AppColor.container).w(1).pSymmetric(h: 8),
            Container(
              height: double.infinity,
              color: Colors.transparent,
              child: VStack([
                // 'Result: 13 Videos'.text.size(11).minFontSize(11).make().pOnly(bottom: 8),
                Obx(
                  () => controller.vList.isEmpty
                      ? ExUiErrorOrEmpty(illustration: Icon(CupertinoIcons.chevron_left_2, size: 32)).expand()
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.65,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: controller.vList.length,
                          itemBuilder: (context, index) {
                            final video = controller.vList[index];
                            return Container(
                              color: AppColor.container,
                              child: ZStack([
                                ExThumbnailV(
                                  imageUrl: video.poster,
                                  videoPath: video.videoPath,
                                  width: 140,
                                  height: 200,
                                ),
                                Container(
                                  color: Vx.black.withAlpha(150),
                                  height: 20,
                                  width: 140,
                                  child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
                                ).positioned(bottom: 0),
                              ]),
                            ).cornerRadius(8).onInkTap(() => controller.onVListTap(video));
                          },
                        ).expand(),
                ),
              ]),
            ).expand(),
          ],
        ).expand(),
      ],
    );
  }
}
