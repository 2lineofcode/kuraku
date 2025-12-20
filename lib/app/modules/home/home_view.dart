import 'package:ex_kit/ex.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import '../../data/database/_init_db.dart';
import '../../utils/helper.dart';
import '../player/player_mini_view.dart';
import '../widgets/widgets.dart';
import 'home_controller.dart';
import 'home_relapse.dart';
import 'page_download/page_download_view.dart';
import 'page_explore/page_explore_view.dart';
import 'page_home/page_home_view.dart';
import 'page_search/page_search_controller.dart';
import 'page_search/page_search_view.dart';
import 'page_settings/page_settings_view.dart';
import 'page_tools/page_tools_view.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        if (event.session.allowedOperations.contains(DropOperation.copy)) {
          return DropOperation.copy;
        } else {
          return DropOperation.none;
        }
      },
      onPerformDrop: controller.onDropEvent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Obx(
            () => MyLayout(
              appBarTitle: appBarTitle(),
              appBarLeading: appBarLeading().pOnly(right: 8),
              isShowAppBarLeading: false,
              appBarAction: appBarAction(),
              sideMenuContent: sideMenuContent(),
              sideMenuWidth: controller.sideMenuWidth.value,
              isDangerMode: controller.isDangerMode.value,
              bodyContent: controller.obx(
                (_) => bodyContent().p8(),
                onLoading: ExUiLoading(
                  message: Obx(() => '${controller.loadingText}'.text.align(TextAlign.center).makeCentered()),
                ),
                onError: (error) {
                  return ExUiErrorOrEmpty(
                    child: VStack(
                      [
                        Icon(UIconsPro.regularRounded.check_circle, size: 48).centered().pOnly(bottom: 16),
                        'Task Done'.text.bold.xl3.makeCentered().pOnly(bottom: 8),
                        '$error'.text.makeCentered().pOnly(bottom: 8),
                        ExButtonElevated(
                            label: 'Restart App',
                            onPressed: () async {
                              controller.loadingText.value = 'Restarting...';
                              controller.change(0, status: RxStatus.loading());
                              await Get.delete<DBService>(force: true);

                              await Get.putAsync(() async {
                                final service = DBService();
                                await service.onReady();
                                return service;
                              });

                              await 2.seconds.delay();
                              await Get.forceAppUpdate();
                              await controller.onRefreshAllContent();
                              await Get.forceAppUpdate();
                              controller.change(200, status: RxStatus.success());
                            }).centered()
                      ],
                    ),
                  );
                },
              ),
              footerContent: footerContent(),
              floatingActionButton: floatingActionButton(),
            ),
          ),
          const PlayerMiniView(),
        ],
      ),
    );
  }

  Widget appBarTitle() {
    if (kDebugMode) {
      return Obx(() => '🐞 ${controller.currentMenuSelected}'.text.size(14).bold.make());
    } else {
      return Obx(() => '${controller.currentMenuSelected}'.text.size(14).bold.make());
    }
  }

  Widget appBarLeading() {
    return 0.heightBox;
  }

  Widget appBarAction() {
    return HStack(
      [
        Obx(
          () => controller.totalVideo.value > 0
              ? CustomPopup(
                  barrierColor: Vx.amber500.withAlpha(50),
                  content: '${HelperBadge.getBadgeTotVidTooltip(controller.totalVideo.value)}'.text.black.size(12).make().w(250),
                  child: Container(
                    decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 16, fillColor: AppColor.selected.withAlpha(100)),
                    child: HStack([
                      HelperBadge.getBadgeTotVidIcons(controller.totalVideo.value).pOnly(right: 8),
                      '${HelperBadge.getBadgeTotVidText(controller.totalVideo.value)}'.text.size(12).make(),
                    ]).pSymmetric(h: 12, v: 4),
                  ),
                )
              : 0.heightBox,
        ).pOnly(right: 8),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.banana, size: 14),
          onPressed: () => HomeRelapse.openMenuRelapse(),
          tooltip: 'Relapse :(',
        ),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.multiple_alt, size: 14),
          onPressed: () => controller.onOpenLibrary(),
          tooltip: 'Library',
        ).pOnly(right: 8),
      ],
    );
  }

  Widget sideMenuContent() {
    if (controller.sideMenuWidth.value != 180) {
      // ** MINI MODE
      return VStack(
        [
          ListView.builder(
            physics: NeverScrollableScrollPhysics(),
            itemCount: controller.menus.length,
            itemBuilder: (context, index) {
              final item = controller.menus[index];
              return Obx(
                () => InkWell(
                  onTap: () => controller.onMenuChange(item['name']),
                  child: Container(
                    decoration: ExDecorator.box(
                      fillColor: item['name'] == controller.currentMenuSelected.value ? AppColor.selected : Colors.transparent,
                      borderColor: Colors.transparent,
                    ),
                    child: HStack([
                      Icon(item['icon'], size: 16).centered(),
                    ]).p(10),
                  ).pSymmetric(h: 10).pOnly(left: 0, bottom: 8),
                ),
              );
            },
          ).wh(60, 280).pOnly(top: 16),
        ],
      );
    }

    // ** NORMAL MODE
    return VStack(
      [
        ListView.builder(
          physics: NeverScrollableScrollPhysics(),
          itemCount: controller.menus.length,
          itemBuilder: (context, index) {
            final item = controller.menus[index];
            return Obx(
              () => InkWell(
                onTap: () => controller.onMenuChange(item['name']),
                child: Container(
                  decoration: ExDecorator.box(
                    fillColor: item['name'] == controller.currentMenuSelected.value ? AppColor.selected : Colors.transparent,
                    borderColor: Colors.transparent,
                  ),
                  child: HStack([
                    Icon(item['icon'], size: 16).pSymmetric(h: 8),
                    '${item['name']}'.text.size(11).make().pOnly(left: 4),
                  ]).p8(),
                ).pSymmetric(h: 10).pOnly(bottom: 8),
              ),
            );
          },
        ).wh(180, 280).pOnly(top: 16),
      ],
    ).expand();
  }

  Widget bodyContent() {
    final List<Widget> pages = [
      PageHomeView(),
      PageSearchView(),
      PageExploreView(),
      PageDownloadView(),
      PageToolsView(),
      PageSettingsView(),
    ];

    int getPageIndex(String menuName) {
      switch (menuName) {
        case kMenuHome: return 0;
        case kMenuSearch: return 1;
        case kMenuExplore: return 2;
        case kMenuDownload: return 3;
        case kMenuTools: return 4;
        case kMenuSetting: return 5;
        default: return 0;
      }
    }

    return Obx(
      () {
        final index = getPageIndex(controller.currentMenuSelected.value);

        if (controller.currentMenuSelected.value == kMenuSearch) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Get.find<PageSearchController>().fnSearch.requestFocus();
          });
        }
        return IndexedStack(index: index, children: pages);
      },
    );
  }

  Widget footerContent() {
    return HStack([
      Spacer(),
      Obx(() => '${controller.footerText}'.text.size(11).ellipsis.maxLines(1).align(TextAlign.end).make().expand()),
    ]).p12();
  }

  Widget floatingActionButton() {
    return 0.heightBox;
  }
}
