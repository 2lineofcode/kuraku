// ignore_for_file: deprecated_member_use

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import '../page_explore/page_explore_controller.dart';
import '../page_search/page_search_overlay.dart';
import 'page_tools_controller.dart';

class PageToolsView extends GetView<PageToolsController> {
  const PageToolsView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        // header
        _buildMenu().h(30).pOnly(bottom: 16),

        // content
        Obx(() {
          switch (controller.currentMenuSelected.value) {
            case kTopLargeFile: return uiTopLargeFileSize().expand();
            case kDuplicate: return uiDuplicateVideo().expand();
            case kTodo: return uiTODO().expand();
            case kAdvanceSearch: return uiAdvanceSearch().expand();
            default: return Container();
          }
        })
      ],
    );
  }

  Widget _buildMenu() {
    return ListView.builder(
      itemCount: controller.menus.length,
      scrollDirection: Axis.horizontal,
      itemBuilder: (context, index) {
        final item = controller.menus[index];
        return Obx(
          () => ExButtonOutline(
            label: item,
            labelSize: 12,
            labelColor: controller.currentMenuSelected.value == item ? Vx.white : Vx.neutral500,
            borderColor: controller.currentMenuSelected.value == item ? AppColor.selected : AppColor.container,
            backgroundColor: controller.currentMenuSelected.value == item ? AppColor.selected : AppColor.container,
            onPressed: () => controller.onMenuChange(item),
          ).pOnly(right: 8),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~ content
  // ────────────────────────────────────────────────────────────────
  Widget uiTopLargeFileSize() {
    return VStack(
      [
        HStack([
          Obx(() => 'Top ${controller.topLargeFileSizeList.length} Large File'.text.make()),
          Spacer(),
          Obx(
            () => ExButtonText(
              label: 'Some file still dont have data quality, Scan now?',
              labelSize: 12,
              onPressed: () async => controller.scanAndUpdateDBVideoQuality(),
            ).pOnly(right: 12).hide(isVisible: controller.isHasDataNotScanned.isFalse),
          ),
        ]).pOnly(bottom: 12),
        controller.topLargeFileSizeList.isEmpty
            ? ExUiErrorOrEmpty(
                child: VStack([
                  Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32).pOnly(bottom: 16).centered(),
                  'No Data'.text.bold.makeCentered().pOnly(bottom: 8),
                  'No Data Found, please add some data'.text.size(12).makeCentered().pOnly(bottom: 12),
                ]).centered(),
              ).pOnly(top: 110)
            : Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(3),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                },
                border: TableBorder.all(width: 0.5, color: Vx.neutral700),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppColor.container),
                    children: [
                      'Code'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Path'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Quality'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Size'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                    ],
                  ),
                  ...List.generate(
                    controller.topLargeFileSizeList.length,
                    (index) {
                      var item = controller.topLargeFileSizeList[index];
                      return TableRow(
                        children: [
                          // code
                          '${item.videoCode.isNotEmptyAndNotNull ? item.videoCode : 'NON-JAV'}'
                              .text
                              .color(item.videoCode.isNotEmptyAndNotNull ? null : Vx.red300)
                              .ellipsis
                              .size(12)
                              .make()
                              .p12()
                              .onInkTap(() async {
                            final video = await DBVideos.getByVideoPath(item.videoPath ?? '');
                            await PageSearchOverlay.onItemTap(video[0]);
                          }),

                          // path
                          if (item.videoPath!.contains('/Volumes')) ...[
                            'External → ${item.videoPath!.getLastSegments(segment: 1)}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                              final video = await DBVideos.getByVideoPath(item.videoPath ?? '');
                              await PageSearchOverlay.onItemTap(video[0]);
                            }),
                          ] else ...[
                            'Local → ${item.videoPath!.getLastPath()}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                              final video = await DBVideos.getByVideoPath(item.videoPath ?? '');
                              await PageSearchOverlay.onItemTap(video[0]);
                            }),
                          ],

                          // quality
                          '${HelperMisc.formatVideoQuality(item.quality ?? '')}'.text.ellipsis.make().tooltip(item.quality ?? '').p12(),

                          // size
                          '${item.filesize?.toFileSize()}'.text.ellipsis.make().p12(),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }

  Widget uiDuplicateVideo() {
    return VStack(
      [
        HStack([
          Obx(() => 'Total Duplicate: ${(controller.duplicateVideoList.length / 2).toInt()}'.text.make()),
          Spacer(),
        ]).pOnly(bottom: 12),
        controller.duplicateVideoList.isEmpty
            ? ExUiErrorOrEmpty(
                child: VStack([
                  Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32).pOnly(bottom: 16).centered(),
                  'No Data'.text.bold.makeCentered().pOnly(bottom: 8),
                  'No Data Duplicate Found 🔥'.text.size(12).makeCentered().pOnly(bottom: 12),
                ]).centered(),
              ).pOnly(top: 110)
            : Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(4),
                },
                border: TableBorder.all(width: 0.5, color: Vx.neutral700),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppColor.container),
                    children: [
                      'Code'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Path'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Size'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                    ],
                  ),
                  ...List.generate(
                    controller.duplicateVideoList.length,
                    (index) {
                      final item = controller.duplicateVideoList[index];
                      return TableRow(
                        children: [
                          // code
                          '${item.videoCode}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                            PageSearchOverlay.onItemTap(item);
                          }),

                          // path
                          if (item.videoPath!.contains('/Volumes')) ...[
                            'External → ${item.videoPath!.getLastSegments(segment: 1)}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                              await PageSearchOverlay.onItemTap(item);
                            }),
                          ] else ...[
                            'Local → ${item.videoPath!.getLastPath()}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                              await PageSearchOverlay.onItemTap(item);
                            }),
                          ],

                          // size
                          '${item.filesize?.toFileSize()}'.text.ellipsis.size(12).make().p12().onInkTap(() async {
                            await PageSearchOverlay.onItemTap(item);
                          }),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }

  Widget uiTODO() {
    return VStack(
      [
        HStack([
          Obx(() => 'Total Todo: ${controller.todoList.length}'.text.make()),
          Spacer(),
          IconButton(
            icon: Icon(UIconsPro.regularRounded.plus, size: 14),
            onPressed: () => controller.addTodo(),
          ),
        ]).pOnly(bottom: 12),
        controller.todoList.isEmptyOrNull
            ? ExUiErrorOrEmpty(
                child: VStack([
                  Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32).pOnly(bottom: 16).centered(),
                  'No Data Found'.text.bold.makeCentered().pOnly(bottom: 2),
                  'You can add todo by clicking the button below'.text.size(12).makeCentered().pOnly(bottom: 12),
                  ExButtonText(
                    label: 'Add New Todo',
                    labelSize: 13,
                    isLabelBold: true,
                    onPressed: () => controller.addTodo(),
                  ).centered(),
                ]).centered(),
              ).pOnly(top: 110)
            : Table(
                columnWidths: const {
                  0: FlexColumnWidth(4),
                  1: FlexColumnWidth(1),
                },
                border: TableBorder.all(width: 0.5, color: Vx.neutral700),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppColor.container),
                    children: [
                      'Todo'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                      'Action'.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
                    ],
                  ),
                  ...List.generate(
                    controller.todoList.length,
                    (index) {
                      final item = controller.todoList[index];
                      return TableRow(
                        children: [
                          // code
                          '${item.message}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                            final code = item.message?.replaceAll('✔︎', '').trim() ?? '';
                            if (code.isValidVideoCode()) {
                              var video = <String, dynamic>{};
                              video['video_code'] = code;
                              HelperOpener.openVideoInfo(video);
                            }
                          }),

                          // action
                          HStack(
                            [
                              IconButton(
                                icon: Icon(UIconsPro.regularRounded.trash, size: 14, color: Vx.neutral400),
                                onPressed: () => controller.deleteTodos(controller.todoList[index]),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }

  Widget uiAdvanceSearch() {
    return HStack([
      _buildLeftPart().pOnly(right: 12),
      _buildRightPart().expand(),
    ]).pOnly(left: 8);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget _buildLeftPart() {
    return Container(
      width: 220,
      height: Get.height,
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: VStack(
        [
          HStack([
            'Filter by: (${controller.leftList.length})'.text.size(11).minFontSize(11).make(),
            Spacer(),
            Obx(
              () => CustomPopup(
                content: VStack([
                  // Actress
                  '${controller.currentFilterBy.value == kActress ? '◉' : '◎'} $kActress'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                    controller.currentFilterBy.value = kActress;
                    await controller.filterByActress();
                    Get.back();
                  }),

                  // Series
                  '${controller.currentFilterBy.value == kSeries ? '◉' : '◎'} $kSeries'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                    controller.currentFilterBy.value = kSeries;
                    await controller.filterBySeries();
                    Get.back();
                  }),

                  // Category
                  '${controller.currentFilterBy.value == kCategory ? '◉' : '◎'} $kCategory'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                    controller.currentFilterBy.value = kCategory;
                    await controller.filterByCategories();
                    Get.back();
                  }),

                  // Year
                  '${controller.currentFilterBy.value == kYear ? '◉' : '◎'} $kYear'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                    controller.currentFilterBy.value = kYear;
                    await controller.filterByYear();
                    Get.back();
                  }),
                ]),
                child: '${controller.currentFilterBy}'.text.minFontSize(11).size(11).make().pSymmetric(h: 8).box.color(AppColor.selected).make().cornerRadius(4),
              ),
            ),
          ]),
          CupertinoTextField(
            controller: controller.tecFilterSearchLeft,
            focusNode: controller.fnFilterSearchLeft,
            placeholder: 'Search (${controller.leftList.length})...',
            style: TextStyle(color: Vx.white, fontSize: 12),
            clearButtonMode: OverlayVisibilityMode.editing,
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            onSubmitted: (s) async => await controller.onLeftListDoSearch(s),
          ).pSymmetric(v: 16),
          FocusScope(
            autofocus: true,
            child: RawKeyboardListener(
              focusNode: controller.leftListFocusNode,
              autofocus: true,
              onKey: (event) {
                if (event is RawKeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    controller.onLeftListKeyPressedArrowDown();
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    controller.onLeftListKeyPressedArrowUp();
                  }
                }
              },
              child: FlutterListView(
                controller: controller.leftListScrollController.value,
                delegate: FlutterListViewDelegate(
                  (context, index) {
                    final item = controller.leftList[index];
                    return VStack(
                      [
                        Obx(
                          () {
                            final isSelected = item['name_en'] == controller.leftListSelected.value;
                            final isHovered = index == controller.leftListHoveredIndex.value;
                            return MouseRegion(
                              onEnter: (_) => controller.leftListHoveredIndex.value = index,
                              onExit: (_) => controller.leftListHoveredIndex.value = -1,
                              child: InkWell(
                                onTap: () async => await controller.onLeftListTap(item, index),
                                child: '${HelperDecensor.decensor(item['name_en'])}'.text.size(11).minFontSize(11).make().w(double.infinity).p4(),
                              )
                                  .color(isSelected ? AppColor.selected : isHovered ? AppColor.border : Colors.transparent)
                                  .cornerRadius(8),
                            );
                          },
                        ),
                        Divider(color: AppColor.border, thickness: 0.5),
                      ],
                    );
                  },
                  childCount: controller.leftList.length,
                ),
              ),
            ),
          ).expand(),
        ],
      ).p12(),
    );
  }

  Widget _buildRightPart() {

    if (controller.leftListSelected.isEmpty) {
      return Container(
        decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
        child: ExUiErrorOrEmpty(
          illustration: Icon(CupertinoIcons.chevron_left_2, size: 32).pOnly(bottom: 12),
          message: 'Please select left area first',
        ),
      );
    }

    return Container(
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: controller.obx(
        (state) => VStack(
          [
            HStack([
              '🏷️ ${controller.leftListSelected}'.text.minFontSize(11).size(11).maxLines(2).ellipsis.make().expand(),
              'Result (${controller.rightList.length})'.text.minFontSize(11).size(11).make().pOnly(left: 16),
            ]).pOnly(bottom: 12),
            _buildVideoList().expand(),
          ],
        ).p12(),
        onLoading: ExUiLoading(
          message: 'Loading...'.text.size(11).minFontSize(11).makeCentered(),
        ),
        onEmpty: ExUiErrorOrEmpty(
          illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
          title: 'No Data Found',
          message: 'No Result Found, as you searched for "${controller.leftListSelected}"',
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.rightList.length,
      itemBuilder: (context, i) {
        final item = controller.rightList[i];
        return ZStack(
          [
            ExThumbnail(
              imageUrl: item['fan_art'] ?? '',
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
              color: Vx.black.withAlpha(150),
              width: 300,
              height: item['title'] != null && item['title'] != '' ? 63 : 33,
              child: VStack([
                '${item['video_code']}'.text.bold.size(12).ellipsis.make().onInkTap(() {
                  HelperMisc.copyToClipboard(item['video_code'], showToast: true);
                }),
                '${HelperDecensor.decensor(item['title'])}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().w(240).hide(isVisible: item['title'] != null && item['title'] != ''),
              ]).p8(),
            ).positioned(bottom: 0, left: 0, right: 0),

            Container(
              color: Vx.black.withAlpha(200),
              width: 70,
              height: 18,
              child: '${item['release_date'].toString().reformatDate(from: kYMd, to: kMdY)}'.text.size(9).minFontSize(9).align(TextAlign.center).ellipsis.makeCentered(),
            ).positioned(left: 0),

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
