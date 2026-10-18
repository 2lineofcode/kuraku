import 'package:dotted_border/dotted_border.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/app_color.dart';
import '../../core/app_shortcut.dart';
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
import 'page_search/page_search_view.dart';
import 'page_settings/page_settings_view.dart';
import 'page_sqleditor/page_sqleditor_view.dart';
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
                        HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: AppStyle.emptyIconSize).centered().pOnly(bottom: 16),
                        'Task Done'.tr.text.bold.xl3.makeCentered().pOnly(bottom: 8),
                        '$error'.text.makeCentered().pOnly(bottom: 8),
                        AppButton(variant: AppButtonVariant.filled,
                            label: 'Restart App'.tr,
                            onPressed: () async {
                              controller.loadingText.value = 'Restarting...'.tr;
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
      return Obx(() => HStack([const HugeIcon(icon: HugeIcons.strokeRoundedBug01, size: AppStyle.iconSize), 6.widthBox, controller.currentMenuSelected.value.tr.text.size(14).bold.make()]));
    } else {
      return Obx(() => '${controller.currentMenuSelected.value.tr}'.text.size(14).bold.make());
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
              return AppIconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize),
                onPressed: controller.focusTopNavSearch,
                tooltip: 'Search: [/]'.tr,
              ).pOnly(right: 8);
            }

            return AppTextField(
              controller: controller.tecTopNavSearch,
              focusNode: controller.fnTopNavSearch,
              enabled: controller.isTopNavSearching.isFalse,
              clearButtonMode: OverlayVisibilityMode.never,
              placeholder: 'Anything...'.tr,
              style: TextStyle(color: AppColor.text),
              prefix: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: Vx.neutral500).pOnly(left: 8),
              suffix: HStack(
                [
                  if (controller.isTopNavSearching.isTrue)
                    CupertinoActivityIndicator(radius: 7).pOnly(right: 8),
                  if (controller.tecTopNavSearch.text.isNotEmpty && controller.isTopNavSearching.isFalse)
                    AppIconButton(
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: Vx.neutral500),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 12,
                      tooltip: 'Clear'.tr,
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
                    child: HelperBadge.getBadgeTotVidIcons(controller.totalVideo.value).p(8),
                  ),
                )
              : 0.heightBox,
        ).pOnly(right: 8),

        Obx(
          () => AppIconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, size: AppStyle.iconSize),
            onPressed: () {
              HomePanelCart.open();
            },
          ).badge(count: controller.cart.length, color: Vx.red500).tooltip(AppShortcut.label('Cart: ⌘ + E'.tr)).hide(isVisible: controller.cart.isNotEmpty),
        ).pOnly(right: 8),

        AppIconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, size: AppStyle.iconSize),
          onPressed: () => HomePanelPlaylist.open(),
          tooltip: AppShortcut.label('Playlist: [⌘ + P]'.tr),
        ).pOnly(right: 8),

        AppIconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCorn, size: AppStyle.iconSize),
          onPressed: () => HomePanelRelapse.open(),
          tooltip: AppShortcut.label('Relapse: [⌘ + .]'.tr),
        ).pOnly(right: 8),
        AppIconButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedLayers01, size: AppStyle.iconSize),
          onPressed: () => HomePanelLibrary.open(),
          tooltip: 'Library'.tr,
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
                      HugeIcon(icon: item['icon'], size: AppStyle.iconSize).centered(),
                    ]).p(10),
                  ).pSymmetric(h: 10).pOnly(left: 0, bottom: 8),
                ).tooltip(item['name']),
              );
            },
          ).wh(60, 280).pOnly(top: 16),
          const Spacer(),
          sqlEditorMenu(),
          chatMenu(),
          settingsMenu(),
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
                    HugeIcon(icon: item['icon'], size: AppStyle.iconSize).pSymmetric(h: 8),
                    '${item['name']}'.tr.text.size(11).make().pOnly(left: 4),
                  ]).p8(),
                ).pSymmetric(h: 10).pOnly(bottom: 8),
              ),
            );
          },
        ).wh(180, 280).pOnly(top: 16),
        const Spacer(),
        sqlEditorMenu(),
        chatMenu(),
        settingsMenu(),
      ],
    ).expand();
  }

  Widget sqlEditorMenu() {
    return Obx(() => AppIconButton(
      style: IconButton.styleFrom(backgroundColor: controller.currentMenuSelected.value == kMenuSqlEditor ? AppColor.selected : Colors.transparent),
      icon: HugeIcon(icon: HugeIcons.strokeRoundedSql, size: AppStyle.iconSize, color: AppColor.text),
      tooltip: kMenuSqlEditor,
      onPressed: () => controller.onMenuChange(kMenuSqlEditor),
    )).pSymmetric(h: 10).w(double.infinity).pOnly(bottom: 12);
  }

  Widget chatMenu() {
    return Obx(() => AppIconButton(
      style: IconButton.styleFrom(backgroundColor: controller.currentMenuSelected.value == kMenuChat ? AppColor.selected : Colors.transparent),
      icon: HugeIcon(icon: HugeIcons.strokeRoundedBubbleChat, size: AppStyle.iconSize, color: AppColor.text),
      tooltip: kMenuChat,
      onPressed: () => controller.onMenuChange(kMenuChat),
    )).pSymmetric(h: 10).w(double.infinity).pOnly(bottom: 12);
  }

  Widget settingsMenu() {
    final isMini = controller.sideMenuWidth.value != 180;
    return Obx(() => InkWell(
      onTap: () => controller.onMenuChange(kMenuSetting),
      child: Container(
        decoration: ExDecorator.box(
          fillColor: controller.currentMenuSelected.value == kMenuSetting ? AppColor.selected : Colors.transparent,
          borderColor: Colors.transparent,
        ),
        child: HStack([
          HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: AppStyle.iconSize).pSymmetric(h: isMini ? 0 : 8),
          if (!isMini) kMenuSetting.tr.text.size(11).make().pOnly(left: 4),
        ], alignment: isMini ? MainAxisAlignment.center : MainAxisAlignment.start).p(isMini ? 10 : 8),
      ),
    ).tooltip(kMenuSetting)).pSymmetric(h: 10).w(double.infinity).pOnly(bottom: 24);
  }

  Widget bodyContent() {
    return Obx(
      () {
        switch (controller.currentMenuSelected.value) {
          case kMenuSearch: return const PageSearchView();
          case kMenuExplore: return const PageExploreView();
          case kMenuDownload: return const PageDownloadView();
          case kMenuTools: return const PageToolsView();
          case kMenuSetting: return const PageSettingsView();
          case kMenuProfile: return const PageProfileView();
          case kMenuSqlEditor: return const PageSqleditorView();
          case kMenuChat: return const PageChatView();
          default: return const PageHomeView();
        }
      },
    );
  }

  Widget footerContent() {
    return HStack([
      Obx(
        () =>
            HStack([const HugeIcon(icon: HugeIcons.strokeRoundedUser, size: AppStyle.smallIconSize), 6.widthBox, '${controller.profile.value.name}'.text.size(11).make()])
                .pSymmetric(h: 10, v: 6)
                .color(AppColor.hover)
                .cornerRadius(6)
                .onInkTap(() => controller.onOpenProfile()),
      ),

      8.widthBox,
      Obx(() => Align(
        alignment: Alignment.centerRight,
        child: footerStatusText().pSymmetric(h: 10, v: 6).color(AppColor.hover).cornerRadius(6),
      )).expand(),
    ]).p12();
  }

  Widget footerStatusText() {
    final footerText = controller.footerText.value;
    final storageText = footerText == controller.idleFooterText ? controller.footerStorageText.value : '';

    if (storageText.isEmpty) {
      return footerText.text.size(11).ellipsis.maxLines(1).align(TextAlign.end).make();
    }

    final usedPct = controller.footerStorageUsedPct.value;
    var color = AppColor.success;
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
                    HugeIcon(icon: HugeIcons.strokeRoundedUpload01, size: AppStyle.emptyIconSize, color: AppColor.text).pOnly(bottom: 12).centered(),
                    'Drop here'.tr.text.bold.size(16).makeCentered().pOnly(bottom: 6),
                    'Drop a folder to add a library\nDrop video files to play instantly'.tr.text.size(12).align(TextAlign.center).color(AppColor.muted).makeCentered(),
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
