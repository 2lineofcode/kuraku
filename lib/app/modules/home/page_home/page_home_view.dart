import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../utils/helper_misc.dart';
import 'page_home_controller.dart';

class PageHomeView extends GetView<PageHomeController> {
  const PageHomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        'Top 10 Trend Video'.text.make(),
        24.heightBox,
        ExButtonElevated(
          label: 'Button',
          onPressed: () => controller.buttonClick(),
        ),
        Obx(
          () => ListView.separated(
            separatorBuilder: (context, index) => Divider(),
            itemCount: controller.videos.length,
            itemBuilder: (context, index) {
              final item = controller.videos[index];
              if (item.title == '') {
                return '${HelperMisc.getLastPath(item.videoPath?.noExt() ?? '')}'.text.make();
              } else {
                return '${item.videoCode} - ${item.title}'.text.make();
              }
            },
          ).h(200),
        ),
      ],
    ).scrollVertical();
  }
}
