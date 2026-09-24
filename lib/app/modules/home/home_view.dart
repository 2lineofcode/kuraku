import 'package:dotted_border/dotted_border.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
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
import 'home_panel/home_panel_cart.dart';
import 'home_panel/home_panel_library.dart';
import 'home_panel/home_panel_playlist.dart';
import 'home_panel/home_panel_relapse.dart';
import 'page_chat/page_chat_view.dart';
import 'page_download/page_download_view.dart';
import 'page_explore/page_explore_view.dart';
import 'page_home/page_home_view.dart';
import 'page_profile/page_profile_view.dart';
import 'page_search/page_search_controller.dart';
import 'page_search/page_search_view.dart';
import 'page_settings/page_settings_view.dart';
import 'page_tools/page_tools_view.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: controller.onDropEnter,
      onDropLeave: controller.onDropLeave,
      onDropEnded: controller.onDropEnded,
      onDropOver: (event) {
        if (HomePanelLibrary.fileDragInProgress) return DropOperation.none;
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
                                await service.init();
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
          dropOverlay(),
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
          () {
            controller.topNavSearchRevision.value;
            if (controller.isTopNavSearchExpanded.isFalse) {
              return IconButton(
                icon: Icon(UIconsPro.regularRounded.search, size: 14),
                onPressed: controller.focusTopNavSearch,
                tooltip: 'Search: [/]',
              ).pOnly(right: 8);
            }

            return CupertinoTextField(
              controller: controller.tecTopNavSearch,
              focusNode: controller.fnTopNavSearch,
              enabled: controller.isTopNavSearching.isFalse,
              clearButtonMode: OverlayVisibilityMode.never,
              placeholder: 'Anything...',
              style: TextStyle(color: AppColor.text, fontSize: 14),
              prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
              suffix: HStack(
                [
                  if (controller.isTopNavSearching.isTrue)
                    CupertinoActivityIndicator(radius: 7).pOnly(right: 8),
                  if (controller.tecTopNavSearch.text.isNotEmpty && controller.isTopNavSearching.isFalse)
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 14, color: Vx.neutral500),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 12,
                      tooltip: 'Clear',
                      onPressed: controller.clearTopNavSearch,
                    ).wh(28, 28),
                ],
              ),
              onChanged: controller.onTopNavSearchChanged,
              onSubmitted: controller.onTopNavSearchSubmitted,
            ).w(180).pOnly(right: 10);
          },
        ),

        Obx(
          () => controller.totalVideo.value > 0
              ? CustomPopup(
                  barrierColor: Vx.amber500.withAlpha(50),
                  content: VStack(
                    [
                      '${HelperBadge.getBadgeTotVidText(controller.totalVideo.value)}'.text.black.size(13).bold.make().pOnly(bottom: 6),
                      '${HelperBadge.getBadgeTotVidTooltip(controller.totalVideo.value)}'.text.black.size(12).make(),
                    ],
                    crossAlignment: CrossAxisAlignment.start,
                  ).w(250),
                  child: Container(
                    decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.selected.withAlpha(100)),
                    child: HelperBadge.getBadgeTotVidIcons(controller.totalVideo.value).p(6),
                  ),
                )
              : 0.heightBox,
        ).pOnly(right: 8),

        Obx(
          () => IconButton(
            icon: Icon(UIconsPro.regularRounded.bags_shopping, size: 14),
            onPressed: () {
              HomePanelCart.open();
            },
          ).badge(count: controller.cart.length, color: Vx.red500).tooltip('Cart: ⌘ + E').hide(isVisible: controller.cart.isNotEmpty),
        ),

        IconButton(
          icon: Icon(UIconsPro.regularRounded.list, size: 14),
          onPressed: () => HomePanelPlaylist.open(),
          tooltip: 'Playlist: [⌘ + P]',
        ),

        IconButton(
          icon: Icon(UIconsPro.regularRounded.banana, size: 14),
          onPressed: () => HomePanelRelapse.open(),
          tooltip: 'Relapse: [⌘ + .]',
        ),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.multiple_alt, size: 14),
          onPressed: () => HomePanelLibrary.open(),
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
                ).tooltip(item['name']),
              );
            },
          ).wh(60, 280).pOnly(top: 16),
          const Spacer(),
          chatMenu(),
        ],
      ).expand();
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
        const Spacer(),
        chatMenu(),
      ],
    ).expand();
  }

  Widget chatMenu() {
    return Obx(() => IconButton(
      style: IconButton.styleFrom(backgroundColor: controller.currentMenuSelected.value == kMenuChat ? AppColor.selected : Colors.transparent),
      icon: Icon(UIconsPro.regularRounded.comment_alt_dots, size: 16, color: AppColor.text),
      tooltip: kMenuChat,
      onPressed: () => controller.onMenuChange(kMenuChat),
    )).pSymmetric(h: 10).w(double.infinity).pOnly(bottom: 4);
  }

  Widget bodyContent() {
    return Obx(
      () {
        switch (controller.currentMenuSelected.value) {
          case kMenuSearch:
            WidgetsBinding.instance.addPostFrameCallback((_) => Get.find<PageSearchController>().activeTab.fnSearch.requestFocus());
            return const PageSearchView();
          case kMenuExplore: return const PageExploreView();
          case kMenuDownload: return const PageDownloadView();
          case kMenuTools: return const PageToolsView();
          case kMenuSetting: return const PageSettingsView();
          case kMenuProfile: return const PageProfileView();
          case kMenuChat: return const PageChatView();
          default: return const PageHomeView();
        }
      },
    );
  }

  Widget footerContent() {
    return HStack([
      Obx(() => '👋🏻 ${controller.profile.value.name}'.text.size(11).make().onInkTap((){
        controller.onOpenProfile();
      })),
      
      Obx(() => footerStatusText().onInkTap((){
        controller.onOpenSettingsAppLog();
      }).expand()),
    ]).p12();
  }

  Widget footerStatusText() {
    final footerText = controller.footerText.value;
    final storageText = footerText.startsWith('Idle | Total Video:') ? controller.footerStorageText.value : '';

    if (storageText.isEmpty) {
      return footerText.text.size(11).ellipsis.maxLines(1).align(TextAlign.end).make();
    }

    final usedPct = controller.footerStorageUsedPct.value;
    var color = Vx.green500;
    if (usedPct >= 90) {
      color = Vx.red600;
    } else if (usedPct > 85) {
      color = Vx.orange500;
    } else if (usedPct > 80) {
      color = Vx.yellow500;
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: footerText),
          TextSpan(text: storageText, style: TextStyle(color: color)),
        ],
      ),
      style: TextStyle(fontSize: 11, color: AppColor.text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
    );
  }

  Widget floatingActionButton() {
    return 0.heightBox;
  }

  Widget dropOverlay() {
    return Obx(
      () => IgnorePointer(
        ignoring: controller.isDropHovering.isFalse,
        child: AnimatedOpacity(
          duration: 150.milliseconds,
          opacity: controller.isDropHovering.value ? 1 : 0,
          child: Material(
            color: Colors.black.withAlpha(222),
            child: Center(
              child: DottedBorder(
                options: RoundedRectDottedBorderOptions(radius: Radius.circular(12), color: Vx.white, strokeWidth: 1),
                child: Container(
                  width: 250,
                  height: 150,
                  decoration: BoxDecoration(color: AppColor.appBar, borderRadius: BorderRadius.circular(12)),
                  child: VStack([
                    Icon(UIconsPro.solidRounded.file_upload, size: 34, color: AppColor.text).pOnly(bottom: 12).centered(),
                    'Drop here'.text.bold.size(16).makeCentered().pOnly(bottom: 6),
                    'Drop a folder to add Library\nDrop a .mp4 file to play instantly'.text.size(12).align(TextAlign.center).color(AppColor.muted).makeCentered(),
                  ]).centered(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
