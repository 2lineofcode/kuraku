import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/notification_service.dart';
import '../../../utils/helper.dart';
import '../home_controller.dart';
import 'page_settings_controller.dart';

class PageSettingsView extends GetView<PageSettingsController> {
  const PageSettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        // ! APP INFO
        HStack(
          [
            // row 1 ~
            Obx(
              () => Container(
                width: 300,
                height: 240,
                decoration: ExDecorator.box(borderColor: AppColor.border),
                child: VStack([
                  HStack([
                    'Application Info'.text.bold.make(),
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
                        '${controller.totalVideos} (${controller.totalFilesize.value.toFileSize()})'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        'Last Relapse'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        Obx(() => '${controller.lastRelapse.value}'.text.size(11).minFontSize(11).bold.make()),
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
                        '${controller.r18TotalVideo.value.numberFormat()}'.text.size(11).minFontSize(11).bold.make(),
                      ]).pOnly(bottom: 8),
                      HStack([
                        'R18 Version'.text.size(11).minFontSize(11).neutral400.make(),
                        Spacer(),
                        Obx(() => '${controller.dbR18Version}'.text.size(11).minFontSize(11).bold.make()),
                      ]),
                    ]).p8(),
                  ),
                ]).p12(),
              ).pOnly(right: 12),
            ),

            // row 2 ~
            Container(
              width: 100,
              height: 240,
              decoration: ExDecorator.box(borderColor: AppColor.border),
              child: VStack(
                [
                  'Sensitif Action'.text.bold.make().pOnly(bottom: 16),
                  VStack(
                    [
                      ExButtonText(
                        label: 'App Log',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => controller.openAppLog(),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Keyboard Shortcuts',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => HelperOpener.openKeyboardShortcuts(),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Go App Folder',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => HelperOpener.openFolder(controller.appSetting.appPath),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Update R18 DB',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => controller.updateR18DB(),
                      ).pOnly(bottom: 8),
                      ExButtonText(
                        label: 'Reset DB',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => controller.onResetAll(),
                      ).pOnly(bottom: 8),
                    ],
                  )
                ],
              ).p12(),
            ).expand(),
          ],
        ).pOnly(bottom: 16),

        // ! APP SETTINGS
        Container(
          decoration: ExDecorator.box(borderColor: AppColor.border),
          width: double.infinity,
          child: VStack(
            [
              'App Settings'.text.bold.make().pOnly(bottom: 12),

              // root
              HStack(
                [
                  // 1
                  Container(
                    decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
                    child: VStack(
                      [
                        HStack(
                          [
                            'Mini Mode'.text.size(12).make().pOnly(right: 12).w(90),
                            Obx(
                              () => Transform.scale(
                                scale: 0.7,
                                child: Switch.adaptive(
                                  value: controller.appMiniMode.value,
                                  onChanged: (val) {
                                    controller.appMiniMode.value = val;
                                    final current = Get.find<HomeController>().sideMenuWidth.value;
                                    if (current == 65) {
                                      Get.find<HomeController>().sideMenuWidth.value = 180;
                                      AppPref.setAppHideSideMenu(false);
                                    } else {
                                      Get.find<HomeController>().sideMenuWidth.value = 65;
                                      AppPref.setAppHideSideMenu(true);
                                    }
                                  },
                                ),
                              ),
                            ).pOnly(right: 12),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Default Player'.text.size(12).make().pOnly(right: 12).w(100),
                            CupertinoTextField(
                              controller: controller.tecDefaultPlayer,
                              readOnly: true,
                              prefix: Icon(CupertinoIcons.play_circle, size: 16).pOnly(left: 8, right: 0, top: 2),
                              suffix: Icon(CupertinoIcons.chevron_down, size: 12).pOnly(right: 12, top: 2),
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              onTap: () => HelperToast.info('coming soon...'),
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),

                        HStack(
                          [
                            'Maximum Coli Per-Day'.text.size(12).make().pOnly(right: 12).w(100),
                            CupertinoTextField(
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              placeholder: '2',
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                      ],
                    ).p12(),
                  ).expand(),

                  12.widthBox,

                  // 2
                  Container(
                    decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
                    child: VStack(
                      [
                        'Player (inApp) Setting'.text.bold.size(13).make().pOnly(bottom: 12),
                        HStack(
                          [
                            'Small Seek'.text.size(12).make().w(100),
                            CupertinoTextField(
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: '5',
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Medium Seek'.text.size(12).make().w(100),
                            CupertinoTextField(
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: '30',
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Long Seek'.text.size(12).make().w(100),
                            CupertinoTextField(
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: '60',
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                      ],
                    ).p12(),
                  ).expand()
                ],
              ),
            ],
          ).p12(),
        ),

        // ! DEBUG FOR TEST ONLY, NOT SHOW IN PROD
        if (kDebugMode) ...[
          Container(
            decoration: ExDecorator.box(borderColor: AppColor.border),
            width: Get.width,
            child: HStack(
              [
                'debug only'.text.make(),
                ExButtonText(
                  label: 'test',
                  onPressed: () async {
                    final notificationModel = NotificationModel(
                      title: 'Hello!',
                      body: 'This is a simple notification',
                      payload: 'notification_data',
                    );

                    await AppNotificationService.show(notificationModel);

                    AppNotificationService.registerNotificationTapHandler((v) {
                      print('payload: $v');
                    });
                  },
                ),
              ],
            ).p8(),
          ).pOnly(top: 12).hide()
        ],
      ],
    ).scrollVertical();
  }
}
