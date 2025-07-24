import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/app_color.dart';
import '../../widgets/widget_thumbnail.dart';
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
              onSubmitted: (s) {
                controller.currentPage.value = 1;
                controller.onSearch(s);
              },
            ).expand(),
          ),
          CustomPopup(
            content: VStack([
              ExButtonText(
                label: 'English',
                labelColor: Colors.black,
                onPressed: () {
                  controller.currentLang.value = 'en';
                  Get.back();
                },
              ),
              ExButtonText(
                label: 'Indonesia',
                labelColor: Colors.black,
                onPressed: () {
                  controller.currentLang.value = 'id';
                  Get.back();
                },
              ),
            ]),
            child: Obx(() => '${controller.currentLang}'.text.uppercase.make().pSymmetric(h: 8).color(Vx.violet500).cornerRadius(90)),
          ).pSymmetric(h: 12),
          Obx(
            () => IconButton(
              icon: Icon(CupertinoIcons.arrowtriangle_left_circle),
              onPressed: controller.currentPage > 1 ? () => controller.onPreviousPage() : null,
            ),
          ),
          Obx(() => '${controller.currentPage}'.text.make().pSymmetric(h: 4)),
          Obx(
            () => IconButton(
              icon: Icon(CupertinoIcons.arrowtriangle_right_circle),
              onPressed: controller.hasNextPage.isTrue ? () => controller.onNextPage() : null,
            ),
          ),
        ]).pOnly(bottom: 24),
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(CupertinoIcons.lab_flask_solid, size: 32),
                  title: controller.currentPage.value == 0 ? '~ Type Something ~' : 'No Data Found',
                  message: controller.currentPage.value == 0 ? 'you can type "Video Code" or "Title" to search' : 'No Result Found, as you searched for "${controller.tecSearch.text}"',
                ).expand()
              : modeWrapView().expand(),
        ),
      ],
    );
  }

  Widget modeWrapView() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (int i = 0; i < controller.videos.length; i++) ...[
          Container(
            color: AppColor.container,
            child: ZStack([
              ExThumbnailV(
                imageUrl: controller.videos[i].fanArt ?? '',
                width: 244,
                height: 180,
                fitUrl: BoxFit.cover,
                withProxy: false,
              ).wh(244, 180),
              Container(
                color: Vx.black.withAlpha(150),
                width: 80,
                height: 20,
                child: VStack([
                  '${controller.videos[i].durationFormated}'.text.size(10).minFontSize(10).maxLines(1).ellipsis.make().pSymmetric(h: 8),
                ]),
              ).positioned(right: 0),
              Container(
                color: Vx.black.withAlpha(150),
                width: 244,
                height: 61,
                child: VStack([
                  '${controller.videos[i].videoCode}'.text.bold.size(12).ellipsis.make(),
                  '${controller.videos[i].title}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().tooltip(controller.videos[i].title ?? ''),
                ]).p8(),
              ).positioned(bottom: 0),
            ]),
          ).cornerRadius(8).onInkTap(() async {
            // ~
            await launchUrlString('https://njavtv.com/en/${controller.videos[i].videoCode}');
          }),
        ],
      ],
    ).scrollVertical();
  }
}
