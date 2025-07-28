import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:process_run/process_run.dart' as cmd;

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../core/app_setting.dart';
import '../../../data/database/db_init.dart';
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
                width: 300,
                decoration: ExDecorator.box(borderColor: AppColor.border),
                child: VStack([
                  HStack([
                    'Application Info'.text.bold.make(),
                    Spacer(),
                    IconButton(onPressed: () => controller.onInit(), icon: Icon(Icons.refresh, size: 16)),
                  ]).pOnly(bottom: 12),

                  // app
                  Container(
                    decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 2),
                    child: VStack([
                      HStack([
                        'Version'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        '(${Env.appVer})'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        'Total Library'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        '${controller.totalLibrary}'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        'Total Video'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        '${controller.totalVideos}'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        'Last Relapse'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        '${controller.lastRelapse}'.text.size(11).minFontSize(11).bold.make(),
                      ]),
                    ]).p8(),
                  ),

                  12.heightBox,

                  // r18
                  Container(
                    decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 2),
                    child: VStack([
                      HStack([
                        'R18 Total Video'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        '${controller.r18TotalVideo}'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        Spacer(),
                        'Check Update'.text.size(11).minFontSize(11).underline.blue500.make().onInkTap(() => controller.updateR18DB()),
                      ]),
                    ]).p8(),
                  ),
                ]).p12(),
              ).pOnly(right: 12),
            ),

            // row 2 ~
            Container(
              width: 100,
              height: 255,
              decoration: ExDecorator.box(borderColor: AppColor.border),
              child: VStack(
                [
                  'Sensitif Action'.text.bold.make().pOnly(top: 8, bottom: 16),
                  VStack(
                    [
                      ExButtonText(
                        label: 'Go App Folder',
                        labelSize: 12,
                        height: 38,
                        onPressed: () => HelperOpener.openFolder(controller.appSetting.appPath),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: '🔄 Relapse',
                        labelSize: 12,
                        height: 38,
                        onPressed: () => controller.onResetRelapse(),
                      ).pOnly(bottom: 8).hide(),
                      ExButtonText(
                        label: 'Update R18 DB',
                        labelSize: 12,
                        height: 38,
                        onPressed: () => controller.updateR18DB(),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Reset DB',
                        labelSize: 12,
                        height: 38,
                        onPressed: () => controller.onResetAll(),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Vacum DB',
                        labelSize: 12,
                        height: 38,
                        onPressed: () => Get.find<DBService>().vacumDB(),
                      ).pOnly(bottom: 8),
                    ],
                  )
                ],
              ).p12(),
            ).expand(),
          ],
          crossAlignment: CrossAxisAlignment.start,
          alignment: MainAxisAlignment.start,
        ).pOnly(bottom: 24),

        // @DEBUG
        VStack(
          [
            ExButtonText(
                label: 'Clear',
                onPressed: () => controller.output.value = '',
            ),

            ExButtonText(
              label: 'Go ~',
              onPressed: () async {
                try {
                  await cmd.run('chmod +x "${Get.find<AppSettingService>().appPath}/dl"');
                } catch (e) {
                  print('Failed to chmod: $e');
                }

                try {
                  await cmd.run(
                    '${Get.find<AppSettingService>().appPath}/dl list',
                    verbose: false,
                    onProcess: (process) {
                      process.outLines.listen((s) {
                        print(s);
                        controller.output.value += s;
                      });
                    },
                  );
                } catch (e) {
                  // await HelperToast.error('e -> $e');
                  controller.output.value = e.toString();
                }
              },
            ),
            Obx(() => '${controller.output}'.text.make()),
          ],
        ),
      ],
    ).scrollVertical();
  }
}
