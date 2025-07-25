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
          IconButton(
            icon: Icon(CupertinoIcons.cloud_download, size: 18),
            onPressed: () => controller.openDialogDownload(),
          ),
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
            Container(
              color: Vx.black.withAlpha(150),
              width: 80,
              height: 20,
              child: VStack([
                '${item.durationFormated}'.text.size(10).minFontSize(10).maxLines(1).ellipsis.make().pSymmetric(h: 8),
              ]),
            ).positioned(right: 0),
            Container(
              color: Vx.black.withAlpha(150),
              width: 300,
              height: 66,
              child: VStack([
                '${item.videoCode}'.text.bold.size(12).ellipsis.make(),
                '${item.title}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().tooltip(item.title ?? ''),
              ]).p8(),
            ).positioned(bottom: 0),
          ]),
        ).cornerRadius(8).onInkTap(() async {
          // ~
          await launchUrlString('https://njavtv.com/en/${item.videoCode}');
        });
      },
    );
  }
}
