import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_color.dart';
import '../../core/const.dart';
import '../widgets/widgets.dart';
import 'home_controller.dart';
import 'page_explore/page_explore_view.dart';
import 'page_files/page_files_view.dart';
import 'page_home/page_home_view.dart';
import 'page_library/page_library_view.dart';
import 'page_settings/page_settings_view.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return MyLayout(
      appBarTitle: appBarTitle(),
      appBarLeading: appBarLeading().pOnly(right: 8),
      isShowAppBarLeading: false,
      appBarAction: appBarAction(),
      sideMenuContent: sideMenuContent(),
      sideMenuWidth: 180,
      bodyContent: Obx(() => bodyContent().p8()),
      footerContent: footerContent(),
      floatingActionButton: floatingActionButton(),
    );
  }

  Widget appBarTitle() {
    return Obx(() => '${controller.currentMenuSelected}'.text.size(14).bold.make());
  }

  Widget appBarLeading() {
    return 0.heightBox;
  }

  Widget appBarAction() {
    return HStack(
      [
        IconButton(
          icon: Icon(CupertinoIcons.collections, size: 18),
          onPressed: () => controller.onOpenLibrary(),
          tooltip: 'Library',
        ).p8(),
      ],
    );
  }

  Widget sideMenuContent() {
    final menuList = <Map<String, dynamic>>[
      {'icon': CupertinoIcons.play_rectangle, 'name': kMenuHome},
      {'icon': CupertinoIcons.doc_text_viewfinder, 'name': kMenuFixMetadata},
      {'icon': CupertinoIcons.rectangle_on_rectangle_angled, 'name': kMenuFiles},
      {'icon': CupertinoIcons.flame, 'name': kMenuExplore},
      {'icon': CupertinoIcons.gear_big, 'name': kMenuSetting},
    ];
    return ListView.builder(
      physics: NeverScrollableScrollPhysics(),
      itemCount: menuList.length,
      itemBuilder: (context, index) {
        final item = menuList[index];
        return Obx(
          () => InkWell(
            onTap: () => controller.onMenuChange(item['name']),
            child: Container(
              decoration: ExDecorator.box(
                fillColor: item['name'] == controller.currentMenuSelected.value ? AppColor.sideMenuSelected : Colors.transparent,
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
    ).pOnly(top: 16).expand();
  }

  Widget bodyContent() {
    switch (controller.currentMenuSelected.value) {
      case kMenuHome:
        return controller.obx((state) => PageHomeView());
      case kMenuFixMetadata:
        return controller.obx((state) => PageLibraryView());
      case kMenuFiles:
        return controller.obx((state) => PageFilesView());
      case kMenuExplore:
        return controller.obx((state) => PageExploreView());
      case kMenuSetting:
        return controller.obx((state) => PageSettingsView());
      default:
        return Container();
    }
  }

  Widget footerContent() {
    return HStack([
      Spacer(),
      Obx(() => '${controller.footerSum}'.text.bold.size(11).make()),
    ]).p12();
  }

  Widget floatingActionButton() {
    return 0.heightBox;
  }
}
