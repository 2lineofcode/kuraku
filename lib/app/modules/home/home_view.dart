import 'package:ex_kit/ex.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
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
      child: Obx(
        () => MyLayout(
          appBarTitle: appBarTitle(),
          appBarLeading: appBarLeading().pOnly(right: 8),
          isShowAppBarLeading: false,
          appBarAction: appBarAction(),
          sideMenuContent: sideMenuContent(),
          sideMenuWidth: controller.sideMenuWidth.value,
          bodyContent: controller.obx(
            (_) => bodyContent().p8(),
            onLoading: ExUiLoading(
              message: Obx(() => '${controller.loadingText}'.text.align(TextAlign.center).makeCentered()),
            ),
          ),
          footerContent: footerContent(),
          floatingActionButton: floatingActionButton(),
        ),
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
        // IconButton(
        //   icon: Icon(UIconsPro.regularRounded.refresh, size: 14),
        //   onPressed: () => controller.onRefreshAllContent(),
        //   tooltip: 'Refresh All Content (⌘+R)',
        // ),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.calendar_minus, size: 14),
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
    final menuList = <Map<String, dynamic>>[
      {'icon': UIconsPro.regularRounded.comet, 'name': kMenuHome},
      {'icon': UIconsPro.regularRounded.magnifying_glass_wave, 'name': kMenuSearch},
      {'icon': UIconsPro.regularRounded.book_alt, 'name': kMenuExplore},
      {'icon': UIconsPro.regularRounded.display_arrow_down, 'name': kMenuDownload},
      {'icon': UIconsPro.regularRounded.customization, 'name': kMenuTools},
      {'icon': UIconsPro.regularRounded.operating_system_upgrade, 'name': kMenuSetting},
    ];

    if (controller.sideMenuWidth.value != 180) {
      return VStack(
        [
          ListView.builder(
            physics: NeverScrollableScrollPhysics(),
            itemCount: menuList.length,
            itemBuilder: (context, index) {
              final item = menuList[index];
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
    return VStack(
      [
        ListView.builder(
          physics: NeverScrollableScrollPhysics(),
          itemCount: menuList.length,
          itemBuilder: (context, index) {
            final item = menuList[index];
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
      Obx(() => '${controller.footerText}'.text.bold.size(11).make()),
    ]).p12();
  }

  Widget floatingActionButton() {
    return 0.heightBox;
  }
}
