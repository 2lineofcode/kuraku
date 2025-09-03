import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
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
                  // ** MODE
                  Obx(
                    () => CustomPopup(
                      content: VStack([
                        'Mode:'.text.black.make().pSymmetric(v: 2),
                        ExButtonText(
                          label: controller.currentMode.value == kModeNet ? '◉ NETWORK (Online)' : '◎ NETWORK (Online)',
                          labelColor: Colors.black,
                          isLabelBold: controller.currentMode.value == kModeNet,
                          onPressed: () {
                            controller.currentMode.value = kModeNet;
                            AppPref.setDownloadMode(kModeNet);
                            Get.back();
                          },
                        ),
                        ExButtonText(
                          label: controller.currentMode.value == kModeDB ? '◉ DATABASE (Offline)' : '◎ DATABASE (Offline)',
                          labelColor: Colors.black,
                          isLabelBold: controller.currentMode.value == kModeDB,
                          onPressed: () {
                            controller.currentMode.value = kModeDB;
                            AppPref.setDownloadMode(kModeDB);
                            Get.back();
                          },
                        ),
                      ]),
                      child: Obx(() => '${controller.currentMode}'
                          .text
                          .size(12)
                          .minFontSize(12)
                          .uppercase
                          .make()
                          .pSymmetric(h: 8)
                          .color(controller.currentMode.value == kModeNet ? Colors.green : Colors.red)
                          .cornerRadius(90)),
                    ).pSymmetric(h: 8),
                  ),

                  // ** LANG
                  Obx(
                    () => CustomPopup(
                      content: VStack([
                        'Language:'.text.black.make().pSymmetric(v: 2),
                        ExButtonText(
                          label: controller.currentLang.value == kLangEn ? '◉ English' : '◎ English',
                          labelColor: Colors.black,
                          isLabelBold: controller.currentLang.value == kLangEn,
                          onPressed: () {
                            controller.currentLang.value = kLangEn;
                            AppPref.setDownloadLang(kLangEn);
                            Get.back();
                          },
                        ),
                        ExButtonText(
                          label: controller.currentLang.value == kLangId ? '◉ Indonesia' : '◎ Indonesia',
                          labelColor: Colors.black,
                          isLabelBold: controller.currentLang.value == kLangId,
                          onPressed: () {
                            controller.currentLang.value = kLangId;
                            AppPref.setDownloadLang(kLangId);
                            Get.back();
                          },
                        ),
                      ]),
                      child: Obx(() => '${controller.currentLang}'.text.uppercase.size(12).make().pSymmetric(h: 8).color(AppColor.selected).cornerRadius(90)),
                    ).pOnly(right: 8).hide(isVisible: controller.currentMode.value == kModeNet),
                  ),
                ],
              ),
              onSubmitted: (s) {
                controller.currentPage.value = 1;
                controller.onSearch(s);
              },
            ).expand(),
          ),
          Obx(
            () => IconButton(
              icon: Icon(
                controller.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                size: controller.isFiltered.isTrue ? 16 : 14,
                color: controller.isFiltered.isTrue ? Vx.red300 : null,
              ),
              onPressed: () => controller.openDialogFilter(),
            ).pOnly(left: 8),
          ),
          IconButton(
            icon: Icon(UIconsPro.regularRounded.arrow_small_down, size: 18),
            onPressed: () => controller.openDownloadLog(),
          ).pOnly(left: 0),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.thinRounded.angle_small_left),
              onPressed: controller.currentPage > 1 ? () => controller.onPreviousPage() : null,
            ),
          ),
          Obx(() => '${controller.currentPage}'.text.make().pSymmetric(h: 4)),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.thinRounded.angle_small_right),
              onPressed: controller.hasNextPage.isTrue ? () => controller.onNextPage() : null,
            ),
          ),
        ]).pOnly(bottom: 12),
        Obx(() => 'Result : ${controller.videos.length} Videos'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
                  title: controller.currentPage.value == 0 ? '~ Type Something ~' : 'No Data Found',
                  message: controller.currentPage.value == 0 ? 'you can type "Video Code" or "Title" to search' : 'No Result Found, as you searched for "${controller.tecSearch.text}"',
                ).expand()
              : modeWrapView().expand(),
        ),
        Obx(
          () => controller.downloadStdout.value.isNotEmpty
              ? HStack([
                  '${controller.downloadStdout}'.text.size(11).minFontSize(11).make(),
                  Spacer(),
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
      itemCount: controller.videos.length,
      itemBuilder: (context, i) {
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
            Container(
              color: Colors.green.withAlpha(100),
              width: 300,
              height: 200,
            ).hide(isVisible: item.match == true),

            // ** is_released (false)
            Container(
              color: Colors.red.withAlpha(70),
              width: 300,
              height: 200,
            ).hide(isVisible: item.isReleased == false && controller.currentMode.value == 'db'),

            // ** has Clicked
            GetBuilder(
              init: HomeController(),
              builder: (controller) {
                return Container(
                  color: Colors.blue.withAlpha(100),
                  width: 300,
                  height: 200,
                ).hide(isVisible: item.isClicked == true);
              },
            ),

            Container(
              color: Vx.black.withAlpha(150),
              width: 80,
              height: 20,
              child: VStack([
                '${item.durationFormated}'.text.size(10).minFontSize(10).maxLines(1).ellipsis.make().pSymmetric(h: 8),
              ]),
            ).positioned(left: 0),

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
                .hide(isVisible: HelperMisc.isValidVideoCode(item.videoCode ?? '')),

            // ** open screenshot
            Icon(UIconsPro.regularRounded.picture, size: 12)
                .wh(30, 30)
                .color(Vx.black)
                .cornerRadius(12)
                .onInkTap(() => HelperOpener.openScreenshot(item))
                .positioned(right: 8, top: 36)
                .hide(isVisible: HelperMisc.isValidVideoCode(item.videoCode ?? '')),

            Container(
              color: Vx.black.withAlpha(150),
              width: 300,
              height: item.title != null && item.title != '' ? 62 : 33,
              child: VStack([
                '${item.videoCode}'.text.bold.size(12).ellipsis.make().onInkTap((){
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
}
