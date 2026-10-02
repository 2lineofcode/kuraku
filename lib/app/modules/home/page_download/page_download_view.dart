import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_media_stack.dart';
import '../../widgets/widget_search_history.dart';
import '../../widgets/widget_search_suggestions_overlay.dart';
import '../../widgets/widget_search_tab_bar.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import 'page_download_controller.dart';
import 'page_download_search_tab.dart';

class PageDownloadView extends GetView<PageDownloadController> {
  const PageDownloadView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true, includeRepeats: false): controller.addTab,
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true, includeRepeats: false): () => controller.closeTab(controller.activeTabIndex.value),
    },
    child: Focus(autofocus: true, child: Column(children: [
      Obx(() => SearchTabBar(
        tabs: controller.tabs.map((tab) => (title: tab.title.value, isLoading: tab.isLoading.value)).toList(),
        activeIndex: controller.activeTabIndex.value,
        scrollController: controller.tabScrollController,
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
              ExButtonText(label: 'Show download', labelSize: 12, onPressed: controller.openDialogDownload),
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
                  child: CupertinoTextField(
                    controller: controller.tecSearch,
                    focusNode: controller.fnSearch,
                    selectAllOnFocus: false,
                    clearButtonMode: OverlayVisibilityMode.editing,
                    placeholder: '${controller.phSearch}',
                    style: TextStyle(color: AppColor.text, fontSize: 14),
                    prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
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
                      ? Container(
                          margin: EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: AppColor.container,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColor.border, width: .5),
                          ),
                          child: VStack(
                            List.generate(controller.commandSuggestions.length, (i) {
                              final item = controller.commandSuggestions[i];
                              final isSelected = controller.selectedCommandIndex.value == i;
                              return Container(
                                width: double.infinity,
                                color: isSelected ? AppColor.selected.withAlpha(90) : Colors.transparent,
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: VStack(
                                  [
                                    item.value.text.size(12).minFontSize(12).bold.make(),
                                    item.description.text.size(10).minFontSize(10).color(AppColor.muted).make().pOnly(top: 2),
                                  ],
                                  crossAlignment: CrossAxisAlignment.start,
                                ),
                              ).onInkTap(() => controller.onPickSearchCommand(item.value));
                            }),
                          ),
                        )
                      : 0.heightBox,
                )),
              ],
            )).expand(),
          ),
          Obx(
            () => ZStack([
              IconButton(
                icon: Icon(
                  controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                  size: controller.filter.isFiltered.isTrue ? 16: 14,
                ),
                onPressed: () => controller.openDialogFilter(isAvailable: () => identical(Get.find<PageDownloadController>().activeTab, controller)),
              ).pOnly(left: 8),

              controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox, 
            ]),
          ),
          IconButton(
            tooltip: 'New download',
            icon: Icon(UIconsPro.regularRounded.plus, size: 14),
            onPressed: () => Get.find<PageDownloadController>().openDialogDownload(),
          ),
          IconButton(
            tooltip: 'Download history',
            icon: Icon(UIconsPro.regularRounded.arrow_small_down, size: 18),
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
          Obx(() => TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColor.text,
              backgroundColor: controller.havingOnly.isFalse ? AppColor.selected : Colors.transparent,
              minimumSize: Size(0, 32),
              padding: EdgeInsets.symmetric(horizontal: 8),
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            onPressed: () => controller.showHavingOnly(false),
            child: Text('Result : ${controller.totalResults}'),
          ).pOnly(bottom: 12).hide(isVisible: controller.allVideos.isNotEmpty)),
          12.widthBox,
          Obx(() => TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Vx.green400,
              backgroundColor: controller.havingOnly.isTrue ? AppColor.selected : Colors.transparent,
              minimumSize: Size(0, 32),
              padding: EdgeInsets.symmetric(horizontal: 8),
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            onPressed: () => controller.showHavingOnly(true),
            child: Text('Having: ${controller.havingVideos}'),
          ).pOnly(bottom: 12).hide(isVisible: controller.allVideos.isNotEmpty)),

          Spacer(),
          Obx(() => 'Page: ${controller.currentPage}'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
          12.widthBox,
          Obx(() => 'Next: ${controller.hasNextPage.isTrue ? 'Yes' : 'No'}'.text.size(10).minFontSize(10).bold.make().pOnly(bottom: 12).hide(isVisible: controller.videos.isNotEmpty)),
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
                  illustration: Icon(UIconsPro.regularRounded.search, size: 128),
                  title: controller.havingOnly.isTrue ? 'No Owned Videos' : controller.currentPage.value == 0 ? '~ Type Something ~' : 'No Data Found',
                  message: controller.havingOnly.isTrue ? 'No owned videos in the loaded results. Click Result to show all.' : controller.currentPage.value == 0 ? 'you can type "Video Code" or "Title" to search' : 'No Result Found, as you searched for "${controller.tecSearch.text}"',
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
          return Container(
            color: AppColor.container,
            child: MediaStack([
              ExThumbnail(
                imageUrl: item.fanArt ?? '',
                videoCode: item.videoCode,
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

            Container(
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                '${item.durationFormated?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).maxLines(1).ellipsis.make(),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(left: 0),

            Container(
              color: Vx.red500.withAlpha(140),
              width: 110,
              height: 18,
              child: VStack([
                'Uncensored Leak'.text.size(10).minFontSize(10).bold.maxLines(1).make().pSymmetric(h: 8),
              ]),
            ).positioned(right: 0, bottom: 62).hide(isVisible: item.isUncensoredLeak == true),

            // ** open trailer
            Icon(UIconsPro.regularRounded.play, size: 12)
                .wh(30, 30)
                .color(Vx.black)
                .cornerRadius(12)
                .onInkTap(() => HelperOpener.openTrailer(item))
                .positioned(right: 8, top: 4)
                .hide(isVisible: item.videoCode?.isValidVideoCode() ?? false),

            // ** open screenshot
            Icon(UIconsPro.regularRounded.picture, size: 12)
                .wh(30, 30)
                .color(Vx.black)
                .cornerRadius(12)
                .onInkTap(() => HelperOpener.openScreenshot(item))
                .positioned(right: 8, top: 36)
                .hide(isVisible: item.videoCode?.isValidVideoCode() ?? false),

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
            HelperOpener.openVideoInfo(item);
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
