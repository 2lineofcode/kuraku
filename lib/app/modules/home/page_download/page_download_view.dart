import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../core/app_color.dart';
import '../../../core/app_shortcut.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_media_stack.dart';
import '../../widgets/widget_search_history.dart';
import '../../widgets/widget_search_suggestions_overlay.dart';
import '../../widgets/widget_search_tab_bar.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import 'page_download_command_dropdown.dart';
import 'page_download_controller.dart';
import 'page_download_search_tab.dart';

class PageDownloadView extends GetView<PageDownloadController> {
  const PageDownloadView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return CallbackShortcuts(
    bindings: {
      const AppShortcut(LogicalKeyboardKey.keyN, includeRepeats: false): controller.addTab,
      const AppShortcut(LogicalKeyboardKey.keyW, includeRepeats: false): () => controller.closeTab(controller.activeTabIndex.value),
    },
    child: Focus(autofocus: true, child: Column(children: [
      Obx(() => SearchTabBar(
        tabs: controller.tabs.map((tab) => (id: tab.id, isPinned: tab.isPinned.value, title: tab.title.value, isLoading: tab.isLoading.value)).toList(),
        activeIndex: controller.activeTabIndex.value,
        scrollController: controller.tabScrollController,
        onReorder: controller.reorderTab, onPin: controller.toggleTabPin,
        onSelect: controller.selectTab,
        onClose: controller.closeTab,
        onAdd: controller.addTab,
      )).pOnly(bottom: 8),
      Expanded(child: Obx(() {
        final tab = controller.activeTab;
        return PageDownloadSearchView(key: ValueKey(tab.id), controller: tab);
      })),
      Obx(() => controller.downloadStdout.value.isNotEmpty
          ? HStack([
              '${controller.downloadStdout}'.text.size(11).minFontSize(11).maxLines(1).make().expand(),
              AppButton(label: 'Show download'.tr, labelSize: 12, onPressed: controller.openDialogDownload),
            ]).pOnly(top: 12)
          : 0.heightBox),
    ])),
    );
  }
}

class PageDownloadSearchView extends StatelessWidget {
  const PageDownloadSearchView({super.key, required this.controller});
  final PageDownloadSearchTab controller;
  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return VStack(
      [
        HStack([
          Obx(
            () => TextFieldTapRegion(child: VStack(
              [
                CallbackShortcuts(
                  bindings: {
                    SingleActivator(LogicalKeyboardKey.arrowDown): () => controller.onCommandArrowDown(),
                    SingleActivator(LogicalKeyboardKey.arrowUp): () => controller.onCommandArrowUp(),
                    SingleActivator(LogicalKeyboardKey.escape): controller.hideSuggestions,
                  },
                  child: AppTextField(
                    controller: controller.tecSearch,
                    focusNode: controller.fnSearch,
                    selectAllOnFocus: false,
                    clearButtonMode: OverlayVisibilityMode.editing,
                    placeholder: controller.phSearch.value.tr,
                    style: TextStyle(color: AppColor.text),
                    prefix: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: Vx.neutral500).pOnly(left: 8),
                    suffix: HStack(
                      [
                        // ** TODO
                      ],
                    ),
                    onTap: controller.showHistory,
                    onChanged: (s) => controller.onSearchTextChanged(s),
                    onSubmitted: (s) => controller.onCommandEnterOrSearch(s),
                  ),
                ),
                Obx(() => SearchHistoryDropdown(
                  suggestions: controller.historySuggestions.toList(),
                  selectedIndex: controller.selectedHistoryIndex.value,
                  onPick: controller.onPickHistory,
                  onDelete: controller.onDeleteHistory,
                  onClear: controller.onClearHistory,
                )),
                SearchSuggestionsOverlay(child: Obx(
                  () => controller.isCommandSuggestionVisible.isTrue
                      ? DownloadCommandDropdown(
                          commands: controller.commandSuggestions.toList(),
                          selectedIndex: controller.selectedCommandIndex.value,
                          onPick: controller.onPickSearchCommand,
                        )
                      : 0.heightBox,
                )),
              ],
            )).expand(),
          ),
          Obx(
            () => ZStack([
              AppIconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFilter,
                  size: AppStyle.iconSize,
                ),
                onPressed: () => controller.openDialogFilter(isAvailable: () => identical(Get.find<PageDownloadController>().activeTab, controller)),
              ).pOnly(left: 8),

              controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
            ]),
          ),
          AppIconButton(
            tooltip: 'New download'.tr,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
            onPressed: () => Get.find<PageDownloadController>().openDialogDownload(),
          ),
          AppIconButton(
            tooltip: 'Download history'.tr,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDownload03, size: AppStyle.iconSize),
            onPressed: () => Get.find<PageDownloadController>().openDownloadLog(),
          ).pOnly(left: 0),

        ], crossAlignment: CrossAxisAlignment.start).pOnly(bottom: 12),

        Obx(() => controller.isLoading.value
            ? const LinearProgressIndicator(minHeight: 2).pOnly(bottom: 12)
            : 0.heightBox),
        Obx(() => controller.error.value.isNotEmpty
            ? Text(controller.error.value, style: const TextStyle(color: Colors.redAccent, fontSize: 12)).pOnly(bottom: 12)
            : 0.heightBox),

        // header
        HStack([
          Obx(() => AppButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColor.text,
              backgroundColor: controller.havingOnly.isFalse ? AppColor.selected : Colors.transparent,
              minimumSize: Size(0, 32),
              padding: EdgeInsets.symmetric(horizontal: 8),
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            onPressed: () => controller.showHavingOnly(false),
            child: Text('Result : @{totalResults}'.trNamed({'totalResults': '${controller.totalResults}'})),
          ).pOnly(bottom: 12).hide(isVisible: controller.allVideos.isNotEmpty)),
          12.widthBox,
          Obx(() => AppButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColor.success,
              backgroundColor: controller.havingOnly.isTrue ? AppColor.selected : Colors.transparent,
              minimumSize: Size(0, 32),
              padding: EdgeInsets.symmetric(horizontal: 8),
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            onPressed: () => controller.showHavingOnly(true),
            child: Text('In Library: @{havingVideos}'.trNamed({'havingVideos': '${controller.havingVideos}'})),
          ).pOnly(bottom: 12).hide(isVisible: controller.allVideos.isNotEmpty)),

          Spacer(),
          Obx(() => 'Page: @{currentPage}'.trNamed({'currentPage': '${controller.currentPage}'}).text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => 'Next: @{No}'.trNamed({'No': '${controller.hasNextPage.isTrue ? 'Yes'.tr : 'No'.tr}'}).text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => '(${controller.videos.length})'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,

        ]),

        // list
        Obx(
          () => controller.isLoading.value
              ? const Center(child: CircularProgressIndicator()).expand()
              : controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.emptyIconSize),
                  title: controller.havingOnly.isTrue ? 'No Owned Videos'.tr : controller.currentPage.value == 0 ? '~ Type Something ~'.tr : 'No Data Found'.tr,
                  message: controller.havingOnly.isTrue ? 'No owned videos in the loaded results. Click Result to show all.'.tr : controller.currentPage.value == 0 ? 'you can type "Video Code" or "Title" to search'.tr : 'No Result Found, as you searched for "@{text}"'.trNamed({'text': '${controller.tecSearch.text}'}),
                ).expand()
              : modeWrapView().expand(),
        ),
      ],
    );
  }

  Widget modeWrapView() {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        controller.onViewportMetricsChanged();
        return false;
      },
      child: GridView.builder(
        key: PageStorageKey('download-results-${controller.id}-${controller.searchRevision}'),
        controller: controller.scrollController,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: 200,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 300 / 200,
        ),
        itemCount: controller.videos.length + (controller.isLoadingMore.isTrue ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= controller.videos.length) {
            return Container(
              color: AppColor.container,
              child: Center(
                child: CupertinoActivityIndicator(radius: 12),
              ),
            ).cornerRadius(8);
          }
          final item = controller.videos[i];
          final releaseDate = DateFormat(kYMd, 'en').tryParseStrict(item.releaseDate?.trim() ?? '');
          return Container(
            color: AppColor.container,
            child: MediaStack([
              ExThumbnail(
                screenshotItems: controller.videos,
                imageUrl: item.fanArt ?? '',
                videoCode: item.videoCode,
                onDownload: item.sourceUrl == null ? null : () => Get.find<PageDownloadController>().downloadWebsite(item.sourceUrl!),
                width: 300,
                height: 200,
                fitUrl: BoxFit.cover,
                withProxy: false,
              ).wh(300, 200),

            // ** match (already have )
            _buildOverlayContainer(
              color: Colors.green.withAlpha(100),
              isVisible: item.match == true,
            ),

            // ** is_released (false)
            _buildOverlayContainer(
              color: Colors.red.withAlpha(70),
              isVisible: item.isReleased == false,
            ),

            // ** has Clicked
            GetBuilder(
              init: HomeController(),
              builder: (controller) {
                return _buildOverlayContainer(
                  color: Colors.blue.withAlpha(100),
                  isVisible: item.isClicked == true,
                );
              },
            ),

            if (releaseDate != null) Container(
              color: AppColor.black180,
              child: HStack([
                HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, size: AppStyle.smallIconSize).pOnly(right: 5),
                releaseDate.toStringEx(format: kMdY).text.size(10).minFontSize(10).maxLines(1).ellipsis.make(),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(left: 0),

            Container(
              color: Vx.red500.withAlpha(140),
              width: 110,
              height: 18,
              child: VStack([
                'Uncensored Leak'.tr.text.size(10).minFontSize(10).bold.maxLines(1).make().pSymmetric(h: 8),
              ]),
            ).positioned(right: 0, bottom: 62).hide(isVisible: item.isUncensoredLeak == true),

            // ** open trailer
            HugeIcon(icon: HugeIcons.strokeRoundedPlay).p(6).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
              HelperOpener.openTrailer(item);
            }).positioned(right: 8, top: 4),

            // ** open screenshot
            HugeIcon(icon: HugeIcons.strokeRoundedImage01).p(6).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
              HelperOpener.openScreenshot(item, items: controller.videos);
            }).positioned(right: 8, top: 36),

            Container(
              color: AppColor.black180,
              width: 300,
              height: item.title != null && item.title != '' ? 63 : 33,
              child: VStack([
                '${item.videoCode}'.text.bold.size(12).ellipsis.make().onInkTap(() {
                  HelperMisc.copyToClipboard(item.videoCode, showToast: true);
                }),
                '${HelperDecensor.decensor(item.title ?? '')}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().w(240).hide(isVisible: item.title != null && item.title != ''),
              ]).p8(),
            ).positioned(bottom: 0, left: 0, right: 0),
            ]),
          ).cornerRadius(8).onInkTap(() {
            HelperOpener.openVideoInfo(item, items: controller.videos);
          });
        },
      ),
    );
  }

  Widget _buildOverlayContainer({required Color color, required bool isVisible}) {
    return Container(
      color: color,
      width: 300,
      height: 200,
    ).hide(isVisible: isVisible);
  }
}
