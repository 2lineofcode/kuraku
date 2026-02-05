import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../../env.g.dart';
import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
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
                        '${controller.totalVideos} (${controller.totalFilesize.value.toFileSizeFormat()})'.text.size(11).minFontSize(11).bold.make(),
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
                        label: 'Vacuum DB',
                        labelSize: 12,
                        height: 32,
                        onPressed: () => controller.onVacuumDB(),
                      ).pOnly(bottom: 8),
                      if (kDebugMode) ...[
                        ExButtonText(
                          label: 'Reset DB',
                          labelSize: 12,
                          height: 32,
                          onPressed: () => controller.onResetAll(),
                        ).pOnly(bottom: 8),
                      ]
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
                            'Search Engine'.text.size(12).make().pOnly(right: 12).w(100),
                            GestureDetector(
                              onTapDown: (details) async {
                                final value = await showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                                  items: [
                                    PopupMenuItem(value: 'NJAV', child: Text('NJAV', style: TextStyle(fontSize: 12))),
                                    PopupMenuItem(value: 'MISSAV', child: Text('MISSAV', style: TextStyle(fontSize: 12))),
                                    PopupMenuItem(value: 'JAVMOST', child: Text('JAVMOST', style: TextStyle(fontSize: 12))),
                                    PopupMenuItem(value: 'SEXTB', child: Text('SEXTB', style: TextStyle(fontSize: 12))),
                                    PopupMenuItem(value: 'JAVGURU', child: Text('JAVGURU', style: TextStyle(fontSize: 12))),
                                  ],
                                );

                                if (value != null) {
                                  controller.tecDefaultSearchEngine.value = value;
                                  AppPref.setDefaultSearchEngine(value);
                                  AppLog.logD('value -> $value');
                                }
                              },
                              child: Container(
                                decoration: ExDecorator.box(borderColor: Color(0xFF2B2A2F), fillColor: Colors.black, borderRadius: 6),
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: HStack(
                                  [
                                    Icon(UIconsPro.regularRounded.web_design, size: 12).pOnly(right: 8),
                                    Obx(
                                      () => Text(
                                        controller.tecDefaultSearchEngine.value.isEmpty ? 'NJAV' : controller.tecDefaultSearchEngine.value.toTitleCase!,
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

        // storage usage
        Obx(() {
          Widget _storageRow(StorageUsage item) {
            final usedPct = item.usedPct;
            var color = Vx.green500;
            if (usedPct >= 90) {
              color = Vx.red600;
            } else if (usedPct >= 80) {
              color = Vx.orange500;
            } else if (usedPct >= 60) {
              color = Vx.yellow500;
            }

            return Container(
              decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
              width: double.infinity,
              child: VStack(
                [
                  HStack([
                    Icon(item.isExternal ? Icons.sd_storage : UIconsPro.boldRounded.laptop, size: 16).pOnly(right: 8),
                    '${item.label}${item.isExternal ? ' (External)' : ''}'.text.bold.size(14).make(),
                    Spacer(),
                    item.path.text.size(10).neutral400.make(),
                  ]).pOnly(bottom: 8),
                  ExProgressBar(
                    value: usedPct.toInt(),
                    color1: color,
                    color2: Vx.neutral500,
                  ).h(8).pSymmetric(h: 12).pOnly(bottom: 8),
                  HStack([
                    'Available: ${item.freeBytes.toFileSizeFormat()}'.text.color(color).size(12).make().pOnly(left: 13),
                    'Used: ${(item.totalBytes - item.freeBytes).toFileSizeFormat()}'.text.size(12).make().pOnly(left: 13),
                    'Total: ${item.totalBytes.toFileSizeFormat()}'.text.size(12).make().pOnly(left: 13),
                    Spacer(),
                    '${usedPct.toStringAsFixed(1)}%'.text.color(color).size(12).make().pOnly(right: 12),
                  ]),
                ],
              ).p12(),
            );
          }

          final isLoading = controller.isLoadingStorage.value;
          final items = controller.storageList;

          return Container(
            decoration: ExDecorator.box(borderColor: AppColor.border),
            width: Get.width,
            child: VStack(
              [
                HStack([
                  'Storage Usage'.text.bold.size(16).make(),
                  Spacer(),
                  IconButton(
                    icon: Icon(UIconsPro.regularRounded.refresh, size: 14),
                    onPressed: () async => await controller.onRefreshStorage(),
                  ),
                ]).pOnly(bottom: 12),
                if (isLoading)
                  Center(child: CupertinoActivityIndicator().pSymmetric(v: 12))
                else if (items.isEmpty)
                  'No storage detected'.text.size(12).neutral400.make().pOnly(bottom: 8)
                else
                  ...items.map((item) => _storageRow(item).pOnly(bottom: 8)),
              ],
            ).p12(),
          ).pOnly(top: 12);
        }),
      ],
    ).scrollVertical();
  }
}
