import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
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
                            GestureDetector(
                              onTapDown: (details) async {
                                final value = await showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                                  items: [
                                    PopupMenuItem(value: 'In App', child: Text('In App', style: TextStyle(fontSize: 12))),
                                    PopupMenuItem(value: 'Default System', child: Text('Default System', style: TextStyle(fontSize: 12))),
                                  ],
                                );

                                if (value != null) {
                                  controller.tecDefaultPlayer.value = value;
                                  AppPref.setDefaultPlayer(value);
                                }
                              },
                              child: Container(
                                decoration: ExDecorator.box(borderColor: Color(0xFF2B2A2F), fillColor: Colors.black, borderRadius: 6),
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: HStack(
                                  [
                                    Icon(CupertinoIcons.play_circle, size: 16).pOnly(right: 8),
                                    Obx(
                                      () => Text(
                                        controller.tecDefaultPlayer.value.isEmpty ? 'Select Player' : controller.tecDefaultPlayer.value,
                                        style: TextStyle(fontSize: 12, color: Vx.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Maximum Coli Per-Day'.text.size(12).make().pOnly(right: 12).w(100),
                            CupertinoTextField(
                              controller: controller.tecAppMaxColi,
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              placeholder: AppPref.getAppMaxColi().toString(),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (s) => AppPref.setAppMaxColi(s.isEmpty ? 0 : int.parse(s)),
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
                              controller: controller.tecPlayerSeekShort,
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: AppPref.getPlayerSeekShort().toString(),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (s) => AppPref.setPlayerSeekShort(s.isEmpty ? 0 : int.parse(s)),
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Medium Seek'.text.size(12).make().w(100),
                            CupertinoTextField(
                              controller: controller.tecPlayerSeekMid,
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: AppPref.getPlayerSeekMid().toString(),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (s) => AppPref.setPlayerSeekMid(s.isEmpty ? 0 : int.parse(s)),
                            ).expand(),
                          ],
                        ).pOnly(bottom: 8),
                        HStack(
                          [
                            'Long Seek'.text.size(12).make().w(100),
                            CupertinoTextField(
                              controller: controller.tecPlayerSeekLong,
                              style: TextStyle(fontSize: 13, color: Vx.white),
                              suffix: 'Seconds'.text.size(12).make().pOnly(right: 12),
                              placeholder: AppPref.getPlayerSeekLong().toString(),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (s) => AppPref.setPlayerSeekLong(s.isEmpty ? 0 : int.parse(s)),
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
                    // final controller = Get.find<HomeController>();
                    // controller.loadingText.value = 'Restarting...';
                    // controller.change(0, status: RxStatus.loading());
                    // await Get.delete<DBService>(force: true);

                    // await Get.putAsync(() async {
                    //   final service = DBService();
                    //   await service.onReady();
                    //   return service;
                    // });

                    // await 2.seconds.delay();
                    // await Get.forceAppUpdate();
                    // await controller.onRefreshAllContent();
                    // await Get.forceAppUpdate();
                    // controller.change(200, status: RxStatus.success());
                  },
                ),
              ],
            ).p8(),
          ).pOnly(top: 12)
        ],
      ],
    ).scrollVertical();
  }
}
