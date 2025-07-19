import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../data/database/db_relapse.dart';
import '../../../utils/helper_opener.dart';
import 'page_settings_controller.dart';

class PageSettingsView extends GetView<PageSettingsController> {
  const PageSettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        HStack(
          [
            // row 1 ~
            Obx(
              () => Container(
                width: 200,
                decoration: ExDecorator.box(borderColor: AppColor.border),
                child: VStack([
                  HStack([
                    'Application Info'.text.bold.make(),
                    Spacer(),
                    IconButton(onPressed: () => controller.onInit(), icon: Icon(Icons.refresh, size: 16)),
                  ]).pOnly(bottom: 12),
                  HStack([
                    'Version'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '(${Env.appVer})'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                  HStack([
                    'R18 Version'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '(${controller.r18Version})'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                  HStack([
                    'Total Library'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '${controller.totalLibrary}'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                  HStack([
                    'Total Video'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '${controller.totalVideos}'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                  HStack([
                    'Total Relapse'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '${controller.totalRelapse}'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                  HStack([
                    'Last Relapse'.text.size(11).minFontSize(11).make(),
                    Spacer(),
                    '${controller.lastRelapse}'.text.size(11).minFontSize(11).bold.make(),
                  ]).pOnly(bottom: 8),
                ]).p12(),
              ).pOnly(right: 12),
            ),

            // row 2 ~
            Container(
              width: 200,
              decoration: ExDecorator.box(borderColor: AppColor.border),
              child: VStack(
                [
                  'Sensitif Action'.text.bold.make().pOnly(top: 8, bottom: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ExButtonOutline(
                        label: 'Go App Folder',
                        borderColor: AppColor.selected,
                        labelSize: 12,
                        height: 38,
                        onPressed: () => HelperOpener.openFolder(controller.appSetting.appDir.path),
                      ),
                      ExButtonOutline(
                        label: 'Reset Relapse',
                        borderColor: AppColor.selected,
                        labelSize: 12,
                        height: 38,
                        onPressed: () => DBRelapse.deleteAll(),
                      ),
                      ExButtonOutline(
                        label: 'Reset All',
                        borderColor: AppColor.selected,
                        labelSize: 12,
                        height: 38,
                        onPressed: () => controller.onResetAll(),
                      ),
                    ],
                  )
                ],
              ).p12(),
            ).expand(),
          ],
          crossAlignment: CrossAxisAlignment.start,
          alignment: MainAxisAlignment.start,
        ).pOnly(bottom: 24),

        'asdkjak'.text.size(12).make(),
      ],
    ).scrollVertical();
  }
}
