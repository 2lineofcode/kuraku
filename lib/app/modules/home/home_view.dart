import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

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
          appBarTitle: controller.appBarShow.isTrue ? appBarTitle() : null,
          appBarLeading: appBarLeading().pOnly(right: 8),
          isShowAppBarLeading: false,
          appBarAction: appBarAction(),
          sideMenuContent: sideMenuContent(),
          sideMenuWidth: controller.sideMenuWidth.value,
          bodyContent: controller.obx(
            (_) => bodyContent().p8(),
            onLoading: ExUiLoading(
              message: Obx(() => '${controller.loadingText}'.text.makeCentered()),
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
      return Obx(() => '[DEBUG] ${controller.currentMenuSelected}'.text.size(14).bold.make());
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
        IconButton(
          icon: Icon(CupertinoIcons.refresh, size: 18),
          onPressed: () => controller.onRefreshAllContent(),
          tooltip: 'Refresh All Content (⌘+R)',
        ),
        IconButton(
          icon: Icon(CupertinoIcons.thermometer, size: 18),
          onPressed: () => HomeRelapse.openMenuRelapse(),
          tooltip: 'Relapse :(',
        ),
        IconButton(
          icon: Icon(CupertinoIcons.collections, size: 18),
          onPressed: () => controller.onOpenLibrary(),
          tooltip: 'Library',
        ),
      ],
    );
  }

  Widget sideMenuContent() {
    final menuList = <Map<String, dynamic>>[
      {'icon': CupertinoIcons.square_stack_3d_down_dottedline, 'name': kMenuHome},
      {'icon': CupertinoIcons.search, 'name': kMenuSearch},
      {'icon': CupertinoIcons.book, 'name': kMenuExplore},
      {'icon': CupertinoIcons.square_arrow_down, 'name': kMenuDownload},
      {'icon': CupertinoIcons.cube_box, 'name': kMenuTools},
      {'icon': CupertinoIcons.gear_big, 'name': kMenuSetting},
    ];
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
                    Icon(item['icon'], size: 18).pSymmetric(h: 8),
                    '${item['name']}'.text.size(11).make().pOnly(left: 4),
                  ]).p8(),
                ).pSymmetric(h: 10).pOnly(bottom: 8),
              ),
            );
          },
        ).wh(300, 280).pOnly(top: 16),
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
