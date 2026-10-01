import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_popup/flutter_popup.dart';

import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_search_tab_bar.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_video_info.dart';
import 'page_explore_controller.dart';

class PageExploreView extends GetView<PageExploreController> {
  const PageExploreView({super.key});

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
        tabs: controller.tabs.map((tab) => (title: tab.title, isLoading: tab.isLoading.value || tab.isLoadingSelection.value || tab.isLoadingR18.value)).toList(),
        activeIndex: controller.activeTabIndex.value,
        scrollController: controller.tabScrollController,
        onSelect: controller.selectTab,
        onClose: controller.closeTab,
        onAdd: controller.addTab,
        addTooltip: 'New Explore tab',
      )).pOnly(bottom: 8),
      Expanded(child: Obx(() {
        final tab = controller.activeTab;
        return PageExploreTabView(key: ValueKey(tab.id), controller: tab);
      })),
    ])),
    );
  }
}

class PageExploreTabView extends StatelessWidget {
  const PageExploreTabView({super.key, required this.controller});
  final PageExploreTab controller;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
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
        _buildFilterMenu().pOnly(bottom: 24),
        Obx(() => controller.error.value.isEmpty ? const SizedBox.shrink() : Text(controller.error.value).pOnly(bottom: 8)),
        HStack([
          _buildLeftPart(),
          Container(height: double.infinity, color: AppColor.container).w(1).pSymmetric(h: 8),
          _buildRightPart().expand(),
        ]).expand(),
      ],
    );
  }

  Widget _buildFilterMenu() {
    return VStack(
      [
        // 'Filter By'.text.size(12).make().pOnly(bottom: 16),
        8.heightBox,
        ListView.builder(
          key: PageStorageKey('explore-menus-${controller.id}'),
          scrollDirection: Axis.horizontal,
          itemCount: controller.menus.length,
          itemBuilder: (context, index) {
            return Obx(
              () => ExButtonOutline(
                label: controller.menus[index],
                labelSize: 12,
                labelColor: controller.currentMenuSelected.value == controller.menus[index] ? AppColor.text : AppColor.muted,
                borderColor: controller.currentMenuSelected.value == controller.menus[index] ? AppColor.selected : AppColor.container,
                backgroundColor: controller.currentMenuSelected.value == controller.menus[index] ? AppColor.selected : AppColor.container,
                onPressed: () => controller.onMenuChange(controller.menus[index]),
              ).pOnly(right: 8),
            );
          },
        ).wh(double.infinity, 30),
      ],
    );
  }

  Widget _buildLeftPart() {
    return Container(
      width: 200,
      height: double.infinity,
      color: Colors.transparent,
      child: VStack(
        [

          HStack(
            [
              Obx(
                () => CupertinoTextField(
                  controller: controller.tecSearchLeft,
                  focusNode: controller.fnSearchLeft,
                  placeholder: controller.phSearchLeft.value,
                  style: TextStyle(color: AppColor.text, fontSize: 12),
                  clearButtonMode: OverlayVisibilityMode.editing,
                  prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
                  onChanged: (s) => controller.onLeftListDoSearch(s),
                ).expand(),
              ),

              Obx(
                () => CustomPopup(
                  contentPadding: EdgeInsets.all(12),
                  content: VStack([
                    'Sort By:'.text.bold.black.make(),
                    Divider(),
                    ExButtonText(
                      label: controller.leftSortSelected.value == 'Name' ? '◉ Name' : '◎ Name',
                      labelSize: 13,
                      labelColor: Vx.black,
                      onPressed: () => {controller.onLeftSortChange('Name'), Get.back()},
                    ).pOnly(right: 6),
                    ExButtonText(
                      label: controller.leftSortSelected.value == 'Count' ? '◉ Count' : '◎ Count',
                      labelSize: 13,
                      labelColor: Vx.black,
                      onPressed: () => {controller.onLeftSortChange('Count'), Get.back()},
                    ),
                  ]).w(100),
                  child: Icon(UIconsPro.regularRounded.sort, size: 12, color: Vx.neutral500).pOnly(left: 8, right: 6),
                ),
              ),
            ],
          ).pSymmetric(v: 8),

          Obx(
            () => controller.leftListFiltered.isEmpty
                ? _buildUiNoData().expand()
                : FocusScope(
                    autofocus: true,
                    child: KeyboardListener(
                      focusNode: controller.leftListFocusNode,
                      autofocus: true,
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            controller.onLeftListKeyPressedArrowDown();
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            controller.onLeftListKeyPressedArrowUp();
                          }
                        }
                      },
                      child: ListView.separated(
                        key: PageStorageKey('explore-left-${controller.id}-${controller.currentMenuSelected.value}'),
                        itemCount: controller.leftListFiltered.length,
                        separatorBuilder: (context, index) => Divider(color: AppColor.border),
                        itemBuilder: (context, index) {
                          final item = controller.leftListFiltered[index];
                          return Obx(
                            () {
                              final isSelected = item == controller.leftListSelected.value;
                              final isHovered = index == controller.leftListHoveredIndex.value;
                              final isPinned = controller.isLeftPinned(item);

                              return MouseRegion(
                                onEnter: (_) => controller.leftListHoveredIndex.value = index,
                                onExit: (_) => controller.leftListHoveredIndex.value = -1,
                                child: InkWell(
                                  onTap: () => controller.onLeftListTap(item),
                                  child: HStack([
                                    // image
                                    if (controller.currentMenuSelected.value == kActress) ...[
                                      item.imgUrl?.trim() != ''
                                          ? ExThumbnail(
                                              imageUrl: '${item.imgUrl?.genAvatarUrl()}',
                                              width: 48,
                                              height: 48,
                                              fitUrl: BoxFit.cover,
                                              withProxy: false,
                                            ).cornerRadius(90)
                                          : ExAvatarView(
                                              source: '',
                                              height: 48,
                                              width: 48,
                                              name: item.name,
                                            ),
                                    ],

                                    // path only
                                    if (controller.currentMenuSelected.value == kPath) ...[
                                      if (HelperMisc.isExternalDrive(item.name)) ...[
                                        'External → ${item.name!.getLastSegments(segment: 1)} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ] else ...[
                                        'Local → ${item.name!.getLastPath()} (${item.count})'.text.size(12).maxLines(3).ellipsis.make().p8().expand(),
                                      ],
                                    ]
                                    // other ~
                                    else ...[
                                      '${item.name} ${item.count != 0 ? '(${item.count})' : ''}'.text.size(12).maxLines(3).ellipsis.make().p8().expand()
                                    ],
                                    IconButton(
                                      tooltip: isPinned ? 'Unpin' : 'Pin to top',
                                      icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 16),
                                      color: isPinned ? Colors.amber : Vx.neutral500,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 48),
                                      onPressed: controller.isSavingPin.value ? null : () => controller.toggleLeftPin(item),
                                    ),
                                  ])
                                      .color(isSelected ? AppColor.selected : isHovered ? AppColor.border : Colors.transparent)
                                      .cornerRadius(8),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ).pOnly(left: 8, top: 8).expand(),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPart() {
    return Container(
      height: double.infinity,
      color: Colors.transparent,
      child: VStack([
        Obx(() => _buildSectionHeader()),
        Obx(
          () => controller.isLoadingSelection.value
              ? const Center(child: CupertinoActivityIndicator()).expand()
              : controller.rightListLocal.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(CupertinoIcons.chevron_left_2, size: 64).pOnly(bottom: 12),
                  message: 'Please select left area first',
                ).expand()
              : controller.rightListViewMode.value == kLocal
                  ? _buildVListLocal().expand()
                  : _buildVListR18().expand(),
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget _buildUiNoData() {
    return ExUiErrorOrEmpty(
      illustration: Icon(UIconsPro.regularRounded.search, size: 64).pOnly(bottom: 24),
      message: 'No Result Found, as you searched for "${controller.tecSearchLeft.text}"',
    );
  }

  Widget _buildSectionHeader() {
    if (controller.rightListLocal.isEmpty) return Container();
    final item = controller.leftListSelected.value;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: ExDecorator.box(borderColor: AppColor.border),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ** actress only
          if (controller.currentMenuSelected.value == kActress) ...[
            item.imgUrl?.trim() == ''
                ? ExAvatarView(source: '', name: item.name, size: 42).centered().pOnly(right: 12)
                : ExThumbnail(
                    imageUrl: '${item.imgUrl?.genAvatarUrl()}',
                    width: 42,
                    height: 42,
                    fitUrl: BoxFit.cover,
                    withProxy: false,
                  ).cornerRadius(90).centered().pOnly(right: 12),
          ] else ...[
            ExAvatarView(
              source: '',
              name: item.name ?? '',
              size: 42,
              bgColor: AppColor.selected,
              textSize: 12,
            ).centered().pOnly(right: 12),
          ],
          VStack([
            '${KanaKit().isKana(HelperDecensor.decensor(item.name!.trim())) ? KanaKit().toRomaji(HelperDecensor.decensor(item.name!.trim())) : HelperDecensor.decensor(item.name!.trim())}'
                .text
                .bold
                .size(12)
                .ellipsis
                .make()
                .onInkTap(() {
              HelperMisc.copyToClipboard(HelperDecensor.decensor(item.name!.trim()), showToast: true);
            }).pOnly(top: 6, bottom: 6),
            Obx(
              () => HStack([
                '$kLocal: ${item.count}'
                    .text
                    .size(11)
                    .minFontSize(11)
                    .maxLines(1)
                    .make()
                    .pOnly(left: 12, right: 12)
                    .color(controller.rightListViewMode.value == kLocal ? AppColor.selected : AppColor.unselected)
                    .cornerRadius(8)
                    .onInkTap(() async => await controller.onSectionLocalTap())
                    .pOnly(right: 12),
                '$kR18: ${controller.rightListR18TotalVideo}'
                    .text
                    .size(11)
                    .minFontSize(11)
                    .maxLines(1)
                    .make()
                    .pOnly(left: 12, right: 12)
                    .color(controller.rightListViewMode.value == kR18 ? AppColor.selected : AppColor.unselected)
                    .cornerRadius(8)
                    .pOnly(right: 12)
                    .onInkTap(() async => await controller.onSectionR18Tap())
                    .pOnly(right: 12)
                    .hide(isVisible: controller.rightListR18TotalVideo.value != 0),
                controller.rightListLocalTotalSize.toFileSizeFormat()
                    .text
                    .size(10)
                    .minFontSize(10)
                    .maxLines(1)
                    .ellipsis
                    .align(TextAlign.right)
                    .make()
                    .tooltip('Total filesize')
                    .pOnly(right: 12)
                    .expand(),
              ]),
            ),
          ]).expand(),

        ],
      ).pSymmetric(h: 8),
    ).pOnly(bottom: 12);
  }

  Widget _buildVListLocal() {
    final double width = 160;
    final double height = 230;

    return GridView.builder(
      key: PageStorageKey(['explore-local', controller.id, controller.currentMenuSelected.value, controller.currentMenuSelected.value == kActress ? controller.leftListSelected.value.id : null, controller.leftListSelected.value.name].join(':')),
      padding: EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: width,
        mainAxisExtent: height,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
      ),
      itemCount: controller.rightListLocal.length,
      itemBuilder: (context, i) {
        final item = controller.rightListLocal[i];

        return RepaintBoundary(
          child: buildLayoutPoster(item, width, height),
        );
      },
    );
  }

  Widget _buildVListR18() {
    return VStack(
      [

        // search & filter
        HStack(
          [
            if (controller.currentMenuSelected.value == kActress) ...[
              HStack([
                Obx(
                  () => CupertinoCheckbox(
                    value: controller.singleActressMode.value,
                    onChanged: (b) {
                      controller.singleActressMode.value = b!;
                      controller.onSectionR18Tap();
                    },
                  ),
                ),
                'Single Actress?'.text.size(12).make().pSymmetric(h: 8),
              ]).onInkTap(() {
                controller.singleActressMode.toggle();
                controller.onSectionR18Tap();
              }),
            ],
            CupertinoTextField(
              controller: controller.tecSearchRight,
              focusNode: controller.fnSearchRight,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: 'Search (${controller.rightListR18Filtered.length}) Videos...',
              style: TextStyle(color: AppColor.text, fontSize: 14),
              prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
              onChanged: (q) => controller.onRightListDoSearch(q),
            ).expand(),

            // 'aaa'.text.size(12).make().pOnly(left: 12),

            // filter
            Obx(
              () => ZStack([
                IconButton(
                  icon: Icon(
                    controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                    size: controller.filter.isFiltered.isTrue ? 16 : 14,
                  ),
                  onPressed: () => controller.openDialogFilter(),
                ).pOnly(left: 8),
                controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
              ]),
            ),
          ],
        ).pOnly(bottom: 12),

        // list
        GridView.builder(
          key: PageStorageKey(['explore-r18', controller.id, controller.currentMenuSelected.value, controller.currentMenuSelected.value == kActress ? controller.leftListSelected.value.id : null, controller.leftListSelected.value.name].join(':')),
          controller: controller.r18ScrollController,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 200,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 300 / 200,
          ),
          itemCount: controller.rightListR18Filtered.length + (controller.isLoadingR18More.isTrue ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= controller.rightListR18Filtered.length) {
              return Container(
                color: AppColor.container,
                child: Center(
                  child: CupertinoActivityIndicator(radius: 12),
                ),
              ).cornerRadius(8);
            }
            final item = controller.rightListR18Filtered[i];
            return MediaStack(
              [
                ExThumbnail(
                  imageUrl: item['fan_art'] ?? '',
                  videoCode: item['video_code'],
                  width: 300,
                  height: 200,
                ).wh(300, 200).cornerRadius(8),

                // ** match (already have )
                _buildOverlayContainer(
                  color: Colors.green.withAlpha(100),
                  isVisible: item['match'] == true,
                ),

                // ** is_released (false)
                _buildOverlayContainer(
                  color: Colors.red.withAlpha(70),
                  isVisible: item['is_released'] == false,
                ),

                // ** has Clicked
                GetBuilder(
                  init: HomeController(),
                  builder: (controller) {
                    return _buildOverlayContainer(
                      color: Colors.blue.withAlpha(100),
                      isVisible: item['is_clicked'] == true,
                    );
                  },
                ),

                Container(
                  color: AppColor.black170,
                  width: 300,
                  height: item['title'] != null && item['title'] != '' ? 63 : 33,
                  child: VStack([
                    '${item['video_code']}'.text.bold.size(12).ellipsis.make().onInkTap(() {
                      HelperMisc.copyToClipboard(item['video_code'], showToast: true);
                    }),
                    '${HelperDecensor.decensor(item['title'] ?? '')}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().w(240).hide(isVisible: item['title'] != null && item['title'] != ''),
                  ]).p8(),
                ).positioned(bottom: 0, left: 0, right: 0),

                if (item['release_date'] != null && item['release_date'] != '') ...[
                  Container(
                    color: AppColor.black180,
                    child: HStack([
                      Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                      '${item['release_date'].toString().reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).align(TextAlign.center).ellipsis.makeCentered(),
                    ]).p4(),
                  ).cornerRadius(8).p2().positioned(left: 0),
                ],

                // ** open trailer
                Icon(UIconsPro.regularRounded.play, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
                  HelperOpener.openTrailer(item);
                }).positioned(right: 8, top: 4),

                // ** open screenshot
                Icon(UIconsPro.regularRounded.picture, size: 12).wh(30, 30).color(Vx.black).cornerRadius(12).onInkTap(() {
                  HelperOpener.openScreenshot(item);
                }).positioned(right: 8, top: 36),
              ],
            ).onInkTap(() async => await HelperOpener.openVideoInfo(item)).pOnly(bottom: 12);
          },
        ).expand()
      ],
    );
  }


  Widget buildLayoutPoster(
    Videos video,
    double width,
    double height, {
    showReleaseDate = true,
    showViewCount = true,
    showQuality = true,
  }) {
    return DoubleTap(
      onSingleTap: () async => await HomePanelVideoInfo.open(video),
      onDoubleTap: () async => await HelperOpener.openVideoFile(video, playlist: controller.rightListLocal.value),
      child: Container(
        color: AppColor.container,
        child: MediaStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            videoPath: video.videoPath,
            width: width,
            height: height,
            prefix: 2.3,
            fitUrl: BoxFit.fitWidth,
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

          // View count
          if (showViewCount) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                Icon(UIconsPro.solidRounded.eye, size: 10).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: ${video.viewCount}' : '').positioned(bottom: 24, right: 4),
          ],

           // Video title
          Container(
            color: AppColor.black180,
            height: 20,
            width: width,
            child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0, left: 0, right: 0),
        ]),
      ).cornerRadius(8).pOnly(right: 8),
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
