import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_search_history.dart';
import '../../widgets/widget_search_tab_bar.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_video_info.dart';
import 'page_search_controller.dart';
import 'page_search_file_drag.dart';
import 'page_search_tab.dart';

class PageSearchView extends GetView<PageSearchController> {
  const PageSearchView({super.key});

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
        return PageSearchTabView(key: ValueKey(tab.id), controller: tab);
      })),
    ])),
    );
  }
}

class PageSearchTabView extends StatelessWidget {
  const PageSearchTabView({super.key, required this.controller});
  final PageSearchTab controller;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(
      () => controller.isFresh.isFalse || controller.isLoading.value || controller.error.value.isNotEmpty
          ? buildPage()
          : ExUiErrorOrEmpty(
              illustration: HugeIcon(icon: HugeIcons.strokeRoundedComputerAdd, size: AppStyle.emptyIconSize),
              title: '~ Fresh ~'.tr,
              message: 'Hi There, Select Or Drag & Drop your JAV Folder Here'.tr,
            ),
    );
  }

  Widget buildPage() {
    return VStack(
      [
        HStack([

          // search
          TextFieldTapRegion(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.arrowDown): controller.onHistoryArrowDown,
                SingleActivator(LogicalKeyboardKey.arrowUp): controller.onHistoryArrowUp,
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
                onTap: controller.showHistory,
                onChanged: controller.onSearchTextChanged,
                onSubmitted: (_) => controller.submitSearch(),
              ),
            ),
            Obx(() => SearchHistoryDropdown(
              suggestions: controller.historySuggestions.toList(),
              selectedIndex: controller.selectedHistoryIndex.value,
              onPick: controller.onPickHistory,
              onDelete: controller.onDeleteHistory,
              onClear: controller.onClearHistory,
            )),
          ])).expand(),

          Obx(() => AppIconButton(
            tooltip: controller.isListView.value ? 'Switch to grid view'.tr :  'Switch to list view'.tr,
            onPressed: controller.toggleViewMode,
            icon: HugeIcon(icon: controller.isListView.value ? HugeIcons.strokeRoundedLayoutList : HugeIcons.strokeRoundedGrid2x2, size: AppStyle.iconSize),
          ).pOnly(left: 4)),

          Obx(
            () => AppIconButton(
              tooltip: controller.isSemanticMode.value ? 'Visual Search On'.tr : 'Visual Search Off'.tr,
              onPressed: controller.toggleSemanticMode,
              icon: controller.isSemanticBusy.value
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : HugeIcon(
                      icon: HugeIcons.strokeRoundedSparkles,
                      size: AppStyle.iconSize,
                      color: controller.isSemanticMode.value ? Vx.amber300 : null,
                    ),
            ).pOnly(left: 4),
          ),

          // filter
          Obx(
            () => ZStack([
              AppIconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFilter,
                  size: AppStyle.iconSize,
                ),
                onPressed: controller.isLoading.value ? null : () => controller.openDialogFilter(isAvailable: () => identical(Get.find<PageSearchController>().activeTab, controller)),
              ).pOnly(left: 8),
              controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
            ]),
          ),

          // sort and quality
          Obx(() {
            final quality = controller.qualityFilter.value;
            return MenuAnchor(
              menuChildren: _sortMenuItems(),
              builder: (context, menu, child) => AppButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColor.selected.withAlpha(150),
                  foregroundColor: AppColor.text,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  controller.hideSuggestions();
                  menu.isOpen ? menu.close() : menu.open();
                },
                icon: HugeIcon(icon: HugeIcons.strokeRoundedSortingZA01, size: AppStyle.iconSize),
                child: Text('${controller.sortBy.value.tr}${quality == 'All qualities' ? '' : ' · ${quality.tr}'}', style: const TextStyle(fontSize: 11)),
              ),
            );
          }).pOnly(left: 8, right: 12),


        ], crossAlignment: CrossAxisAlignment.center).pOnly(bottom: 8),


        Obx(() => controller.isSemanticMode.value || controller.isSearchMode.isTrue || controller.selectedVideos.isNotEmpty
            ? HStack(
                [
                  Expanded(child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    '${controller.videos.length} ${controller.videos.length == 1 ? 'video'.tr : 'videos'.tr}'.text.size(12).make(),
                    if (controller.isSemanticMode.value) ...[
                      Tooltip(
                        message: 'Visual matches'.tr,
                        child: AppDropdown<String>(
                          value: controller.visualSensitivity.value,
                          isDense: true,
                          style: TextStyle(color: AppColor.text),
                          dropdownColor: AppColor.panel,
                          items: ['Strict', 'Balanced', 'Broad'].map((value) => DropdownMenuItem(value: value, child: Text(value.tr))).toList(),
                          onChanged: (value) { if (value != null) controller.setVisualSensitivity(value); },
                        ),
                      ),
                      AppIconButton(
                        tooltip: 'Search settings\n@{value}'.trNamed({'value': '${controller.semanticCoverage.value.isEmpty ? 'Describe the image in English. Search uses one frame per video.'.tr : controller.semanticCoverage.value}'}),
                        visualDensity: VisualDensity.compact,
                        onPressed: Get.isRegistered<HomeController>() ? () => Get.find<HomeController>().onMenuChange(kMenuSetting) : null,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: AppStyle.iconSize),
                      ),
                    ],
                  ])),
                  if (controller.selectedVideos.isNotEmpty)
                    AppButton(
                      onPressed: controller.selectedVideos.clear,
                      child: Text(
                        '@{length} selected · Clear'.trNamed({'length': '${controller.selectedVideos.length}'}),
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (controller.videos.isNotEmpty) ...[
                    'PLAY ALL'.tr.text.underline.size(12).make().pOnly(right: 16).onInkTap(() {
                      controller.performSelectionAction('play', controller.videos.toList());
                    }),
                  ],
                ],
              ).pOnly(bottom: 8)
            : 0.heightBox),

        Obx(
          () => controller.isLoading.value
              ? const Center(child: CircularProgressIndicator()).expand()
              : controller.error.value.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(controller.error.value, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      AppButton(variant: AppButtonVariant.outlined, onPressed: controller.onSearch, child: Text('Retry'.tr)),
                      if (controller.isSemanticMode.value) AppButton(onPressed: controller.toggleSemanticMode, child: Text('Use regular search'.tr)),
                    ]),
                  ],
                ))).expand()
              : controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: AppStyle.emptyIconSize),
                  title: 'No Data Found'.tr,
                  message: controller.isSemanticMode.value
                      ? 'Try a simpler English description, Broad matches, or check your filters.'.tr
                      : 'No Result Found, as you searched for "@{text}"\nor Add some video to your library first.'.trNamed({'text': '${controller.tecSearch.text}'}),
                ).expand()
              : (controller.isListView.value ? modeListView() : modeGridView()).expand(),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  List<Widget> _sortMenuItems() => [
    Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Sort by'.tr, style: TextStyle(fontSize: 11, color: Colors.grey))),
    for (final sort in [if (controller.isSemanticMode.value) 'Relevance', 'Random', 'Release Date', 'View Count', 'File Size'])
      MenuItemButton(
        onPressed: () => controller.onSortByChange(sort),
        leadingIcon: HugeIcon(icon: controller.sortBy.value == sort ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCircle, size: AppStyle.iconSize),
        child: Text(sort.tr, style: const TextStyle(fontSize: 13)),
      ),
    Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Quality'.tr, style: TextStyle(fontSize: 11, color: Colors.grey))),
    for (final quality in ['All qualities', 'FHD only', 'HD only'])
      MenuItemButton(
        onPressed: () => controller.onQualityFilterChange(quality),
        leadingIcon: HugeIcon(icon: controller.qualityFilter.value == quality ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCircle, size: AppStyle.iconSize),
        child: Text(quality.tr, style: const TextStyle(fontSize: 13)),
      ),
  ];

  Widget _buildSelectableItem(Videos video, Widget child) {
    return SearchFileDrag(controller: controller, video: video, child: scm.ContextMenuWidget(
      contextMenuIsAllowed: (_) => controller.selectedVideos.isNotEmpty,
      menuProvider: (_) {
        if (controller.isClosed || controller.selectedVideos.isEmpty) return null;
        if (!controller.selectedVideos.contains(video)) controller.selectedVideos.assignAll([video]);
        final selected = controller.videos.where(controller.selectedVideos.contains).toList();
        final revision = controller.searchRevision;
        scm.MenuAction action(String title, String value) => scm.MenuAction(title: title, callback: () async {
          if (controller.isClosed || revision != controller.searchRevision) return;
          try {
            await controller.performSelectionAction(value, selected);
          } catch (e) {
            AppLog.logE('Search selection action failed ($value): $e');
            await HelperToast.error(e.toString());
          }
        });
        return scm.Menu(children: [
          action('Play as Playlist'.tr, 'play'),
          action('Play in Grid Player'.tr, 'playMulti'),
          scm.MenuSeparator(),
          action('Add to cart'.tr, 'cart'),
          action('Add to Playlist'.tr, 'playlist'),
          action('Add to favorite'.tr, 'favorite'),
        ]);
      },
      child: DoubleTap(
        onCommandTap: () => controller.toggleSelection(video),
        onSingleTap: () async {
          controller.selectedVideos.clear();
          await HomePanelVideoInfo.open(video);
        },
        onDoubleTap: () async {
          controller.selectedVideos.clear();
          await HelperOpener.openVideoFile(video);
        },
        child: Obx(() => Semantics(
          selected: controller.selectedVideos.contains(video),
          child: Stack(children: [
            child,
            if (controller.selectedVideos.contains(video))
              Positioned.fill(child: IgnorePointer(child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(55),
                  border: Border.all(color: Colors.lightBlueAccent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ))),
          ]),
        )),
      ),
    ));
  }

  Widget modeListView() {
    return ListView.separated(
      key: PageStorageKey('search-list-${controller.id}-${controller.searchRevision}'),
      controller: controller.scrollGridController,
      padding: EdgeInsets.all(8),
      itemCount: controller.videos.length,
      separatorBuilder: (context, index) => SizedBox(height: 8),
      itemBuilder: (context, index) {
        final video = controller.videos[index];
        final actresses = (video.actress ?? []).map((item) => item.nameRomaji ?? '').where((name) => name.isNotEmpty).join(', ');
        final details = [
          if (video.quality.isNotEmptyAndNotNull) HelperMisc.formatVideoQuality(video.quality ?? ''),
          if (video.filesize != null) video.filesize!.toFileSizeFormat(),
          '@{viewCount} views'.trNamed({'viewCount': '${video.viewCount ?? 0}'}),
        ].join(' · ');
        return _buildSelectableItem(video, Container(
            padding: EdgeInsets.all(8),
            decoration: ExDecorator.box(fillColor: AppColor.container, borderColor: Colors.transparent, borderRadius: 8),
            child: Row(
              children: [
                SizedBox(width: 260, height: 170, child: buildLayoutPoster(video, 260, 170, isFanArt: true, interactive: false)),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (video.videoCode.isNotEmptyAndNotNull) ...[
                        Text(video.videoCode!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                      ],
                      Text(video.title ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12)).tooltip(video.videoPath ?? ''),
                      if (actresses.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Text(actresses, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                      ],
                      SizedBox(height: 8),
                      Text(details, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget modeGridView() {
    double width = 150;
    double height = 230;

    return GridView.builder(
      key: PageStorageKey('search-results-${controller.id}-${controller.searchRevision}'),
      controller: controller.scrollGridController,
      padding: EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: width,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: width / height,
      ),
      itemCount: controller.videos.length,
      itemBuilder: (context, i) {
        final item = controller.videos[i];
        return RepaintBoundary(
          child: buildLayoutPoster(item, width, height),
        );
      },
    );
  }



  Widget buildLayoutPoster(
    Videos video,
    double width,
    double height, {
    bool isFanArt = false,
    bool interactive = true,
    showReleaseDate = true,
    showViewCount = true,
    showQuality = true,
  }) {
    final child = Container(
        color: AppColor.container,
        child: MediaStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            videoPath: video.videoPath,
            width: width,
            height: height,
            prefix: isFanArt ? 1 : 2.3,
            fitUrl: isFanArt ? BoxFit.cover : BoxFit.fitWidth,
            fitMemory: isFanArt ? BoxFit.fitWidth : BoxFit.cover,
            contextMenuIsAllowed: (_) => controller.selectedVideos.isEmpty,
          ),

          Positioned.fill(
            child: Obx(() => Get.find<HomeController>().isInCart(video)
                ? IgnorePointer(
                    child: Semantics(
                      label: 'In panel cart'.tr,
                      child: Container(
                        color: Colors.blue.withAlpha(85),
                        alignment: Alignment.center,
                        child: const HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, color: Colors.white, size: AppStyle.largeIconSize),
                      ),
                    ),
                  )
                : const SizedBox.shrink()),
          ),

          // sub id?
          if (video.videoPath?.isHasIdSub() == true) ...[
            Container(
              color: Vx.blue600.withAlpha(200),
              child: HStack([
                const HugeIcon(icon: HugeIcons.strokeRoundedClosedCaption, size: AppStyle.smallIconSize).tooltip('ID Sub'.tr),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

           // sub en?
          if (video.videoPath?.isHasEnSub() == true) ...[
            Container(
              color: Vx.purple600.withAlpha(200),
              child: HStack([
                const HugeIcon(icon: HugeIcons.strokeRoundedClosedCaption, size: AppStyle.smallIconSize).tooltip('EN Sub'.tr),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // reduce mosaic?
          if (video.videoPath?.isHasUncensored() == true) ...[
            Container(
              color: Vx.red600.withAlpha(200),
              child: HStack([
                const HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.smallIconSize).tooltip('Reduce Mosaic'.tr),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // Release date
          if (showReleaseDate) ...[
            Container(
              color: AppColor.black180,
              child: HStack([
                HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, size: AppStyle.smallIconSize).pOnly(right: 5),
                video.releaseDate.isNotEmptyAndNotNull
                    ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: @{kMdY}'.trNamed({'kMdY': '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'}))
                    : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: @{kMdY}'.trNamed({'kMdY': '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'}))
              ]).p4(),
            ).cornerRadius(8).p2(),
          ],

          // Quality
          if (video.quality.isNotEmptyAndNotNull) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                '${HelperMisc.formatVideoQuality(video.quality ?? '').maxWords(1)}'.text.orange500.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.filesize?.toFileSizeFormat() != null ? '${video.filesize?.toFileSizeFormat()}' : '').positioned(bottom: 24, left: 4)
          ],

          if (controller.semanticScoreByVideoId[(video.id ?? '').trim()] != null) ...[
            Container(
              color: Vx.amber700.withAlpha(220),
              child: HStack([
                (controller.semanticReasonByVideoId[(video.id ?? '').trim()] ?? 'Match').tr.text.black.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).positioned(bottom: 24, right: 4),
          ],

          // View count
          if (showViewCount) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                HugeIcon(icon: HugeIcons.strokeRoundedView, size: AppStyle.smallIconSize).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: @{count}'.trNamed({'count': '${video.viewCount}'}) : '').positioned(bottom: 46, right: 4),
          ],

           // Video title
          Container(
            color: AppColor.black180,
            height: 20,
            width: width,
            child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0, left: 0, right: 0),
        ]),
      ).cornerRadius(8).pOnly(right: 8);
    return interactive ? _buildSelectableItem(video, child) : child;
  }

}
