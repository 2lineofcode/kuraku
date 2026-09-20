import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
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
    return Column(children: [
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
        return PageSearchTabView(key: ValueKey(tab.id), controller: tab);
      })),
    ]);
  }
}

class PageSearchTabView extends StatelessWidget {
  const PageSearchTabView({super.key, required this.controller});
  final PageSearchTab controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => controller.isFresh.isFalse || controller.isLoading.value || controller.error.value.isNotEmpty
          ? buildPage()
          : ExUiErrorOrEmpty(
              illustration: Icon(UIconsPro.regularRounded.square_dashed_circle_plus, size: 128),
              title: '~ Fresh ~',
              message: 'Hi There, Select Or Drag & Drop your JAV Folder Here',
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
              child: CupertinoTextField(
                controller: controller.tecSearch,
                focusNode: controller.fnSearch,
                selectAllOnFocus: false,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: '${controller.phSearch.value}',
                style: TextStyle(color: Vx.white, fontSize: 14),
                prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
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

          Obx(() => IconButton(
            tooltip: controller.isListView.value ? 'Switch to grid view' : 'Switch to list view',
            onPressed: controller.toggleViewMode,
            icon: Icon(controller.isListView.value ? Icons.grid_view_rounded : Icons.view_list_rounded, size: 18),
          ).pOnly(left: 4)),

          Obx(
            () => IconButton(
              tooltip: controller.isSemanticMode.value ? 'AI Search On' : 'AI Search Off',
              onPressed: controller.toggleSemanticMode,
              icon: controller.isSemanticBusy.value
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : Icon(
                      controller.isSemanticMode.value
                          ? UIconsPro.boldRounded.sparkles
                          : UIconsPro.regularRounded.sparkles,
                      size: controller.isSemanticMode.value ? 16 : 14,
                      color: controller.isSemanticMode.value ? Vx.amber300 : null,
                    ),
            ).pOnly(left: 4),
          ),

          // filter
          Obx(
            () => ZStack([
              IconButton(
                icon: Icon(
                  controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                  size: controller.filter.isFiltered.isTrue ? 16 : 14,
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
              builder: (context, menu, child) => TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: AppColor.selected.withAlpha(150),
                  foregroundColor: Colors.white,
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
                icon: Icon(UIconsPro.regularRounded.sort, size: 12),
                label: Text('${controller.sortBy.value}${quality == 'All qualities' ? '' : ' · $quality'}', style: const TextStyle(fontSize: 11)),
              ),
            );
          }).pOnly(left: 8, right: 12),

          
        ], crossAlignment: CrossAxisAlignment.center).pOnly(bottom: 24),


        Obx(() => controller.isSearchMode.isTrue || controller.selectedVideos.isNotEmpty
            ? HStack(
                [
                  '${controller.semanticResultLabel.value.isEmpty ? 'Result' : controller.semanticResultLabel.value}: ${controller.videos.length} Videos'.text.size(12).make(),
                  Spacer(),
                  if (controller.selectedVideos.isNotEmpty)
                    TextButton(
                      onPressed: controller.selectedVideos.clear,
                      child: Text(
                        '${controller.selectedVideos.length} selected · Clear',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (controller.videos.isNotEmpty) ...[
                    'PLAY ALL'.text.underline.size(12).make().pOnly(right: 16).onInkTap(() {
                      HelperOpener.openVideoFile(controller.videos.first, playlist: controller.videos);
                    }),
                  ],
                ],
              ).pOnly(bottom: 16)
            : 0.heightBox),
        
        Obx(
          () => controller.isLoading.value
              ? const Center(child: CircularProgressIndicator()).expand()
              : controller.error.value.isNotEmpty
              ? Center(child: Text(controller.error.value)).expand()
              : controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
                  title: 'No Data Found',
                  message: 'No Result Found, as you searched for "${controller.tecSearch.text}"\nor Add some video to your library first.',
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
    const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Sort by', style: TextStyle(fontSize: 11, color: Colors.grey))),
    for (final sort in ['Random', 'Release Date', 'View Count', 'File Size'])
      MenuItemButton(
        onPressed: () => controller.onSortByChange(sort),
        leadingIcon: Icon(controller.sortBy.value == sort ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 16),
        child: Text(sort, style: const TextStyle(fontSize: 13)),
      ),
    const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Quality', style: TextStyle(fontSize: 11, color: Colors.grey))),
    for (final quality in ['All qualities', 'FHD only', 'HD only'])
      MenuItemButton(
        onPressed: () => controller.onQualityFilterChange(quality),
        leadingIcon: Icon(controller.qualityFilter.value == quality ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 16),
        child: Text(quality, style: const TextStyle(fontSize: 13)),
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
            await HelperToast.error(e.toString());
          }
        });
        return scm.Menu(children: [
          action('Play as Playlist', 'play'),
          action('Play in Grid Player', 'playMulti'),
          scm.MenuSeparator(),
          action('Add to cart', 'cart'),
          action('Add to Playlist', 'playlist'),
          action('Add to favorite', 'favorite'),
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
          '${video.viewCount ?? 0} views',
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
                        Text(actresses, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Vx.neutral400)),
                      ],
                      SizedBox(height: 8),
                      Text(details, style: TextStyle(fontSize: 11, color: Vx.neutral400)),
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
        child: ZStack([
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
                      label: 'In panel cart',
                      child: Container(
                        color: Colors.blue.withAlpha(85),
                        alignment: Alignment.center,
                        child: const Icon(Icons.shopping_bag, color: Colors.white, size: 24),
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
                '🇮🇩'.text.size(10).minFontSize(10).make().tooltip('ID Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

           // sub en?
          if (video.videoPath?.isHasEnSub() == true) ...[
            Container(
              color: Vx.purple600.withAlpha(200),
              child: HStack([
                '🇬🇧'.text.size(10).minFontSize(10).make().tooltip('EN Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // reduce mosaic?
          if (video.videoPath?.isHasUncensored() == true) ...[
            Container(
              color: Vx.red600.withAlpha(200),
              child: HStack([
                '🎞️'.text.size(10).minFontSize(10).make().tooltip('Reduce Mosaic'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // Release date
          if (showReleaseDate) ...[
            Container(
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                video.releaseDate.isNotEmptyAndNotNull
                    ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}')
                    : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: ${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}')
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
                'AI ${(controller.semanticScoreByVideoId[(video.id ?? '').trim()]! * 100).toStringAsFixed(0)}%'.text.black.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).positioned(bottom: 24, right: 4),
          ],

          // View count
          if (showViewCount) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                Icon(UIconsPro.solidRounded.eye, size: 10).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: ${video.viewCount}' : '').positioned(bottom: 46, right: 4),
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
