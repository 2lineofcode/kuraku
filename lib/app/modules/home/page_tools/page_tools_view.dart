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
import '../home_panel/home_panel_video_info.dart';
import '../page_explore/page_explore_controller.dart';
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
            case kWatchNextQueue: return uiWatchNextQueue().expand();
            case kHealthDashboard: return uiHealthDashboard().expand();
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
    if (controller.topLargeFileSizeList.isEmpty) {
      return ExUiErrorOrEmpty(
         illustration: Icon(UIconsPro.regularRounded.square_dashed_circle_plus, size: 128),
        title: '~ Fresh ~',
        message: 'Hi There, Select Or Drag & Drop your JAV Folder Here',
      );
    }
    return VStack(
      [
        // ** options
        HStack([
          Obx(() => 'Top ${controller.topLargeFileSizeList.length} Large File'.text.make()),
          Obx(
            () => ExButtonText(
              label: 'Re-Scan',
              labelSize: 12,
              onPressed: () async => controller.scanAndUpdateDBVideoRes(),
            ).badge(size: 6, color: Vx.red500, position: VxBadgePosition.right).pOnly(right: 12).hide(isVisible: controller.isHasDataNotScanned.isFalse),
          ),
          Spacer(),

          HStack([
            GestureDetector(
              onTapDown: (details) async {
                final value = await showMenu<String>(
                  context: Get.context!,
                  position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                  items: [
                    PopupMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 12))),
                    PopupMenuItem(value: 'internal', child: Text('Internal', style: TextStyle(fontSize: 12))),
                    PopupMenuItem(value: 'external', child: Text('External', style: TextStyle(fontSize: 12))),
                  ],
                );

                if (value != null) {
                  controller.topLargeFilterMode.value = value;
                  await controller.getTopLargeFileSize(mode: value);
                }
              },
              child: Container(
                width: 100,
                decoration: ExDecorator.box(borderColor: Color(0xFF2B2A2F), fillColor: Colors.black, borderRadius: 6),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: HStack(
                  [
                    Icon(UIconsPro.regularRounded.filter, size: 12).pOnly(right: 12),
                    Obx(
                      () => Text(
                        controller.topLargeFilterMode.value.isEmpty ? '<select>' : controller.topLargeFilterMode.value.toTitleCase!,
                        style: TextStyle(fontSize: 12, color: Vx.white),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ]).pOnly(right: 12),

          
        ]).pOnly(bottom: 12),

        // ** content 
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(width: .5, color: Vx.neutral700)
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColor.container,
                    border: Border(
                      bottom: BorderSide(width: .5, color: Vx.neutral700)
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildHeaderCell('Code', flex: 1),
                      _buildHeaderCell('Path', flex: 3),
                      _buildHeaderCell('Quality', flex: 1),
                      _buildHeaderCell('Size', flex: 1, isLast: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Obx(
                    () {
                      final hoveredIndex = controller.topLargeHoveredIndex.value;
                      return ListView.builder(
                        itemCount: controller.topLargeFileSizeList.length,
                        itemBuilder: (context, index) {
                        final item = controller.topLargeFileSizeList[index];
                        final videoPath = item.videoPath ?? '';
                        final isExternal = HelperMisc.isExternalDrive(videoPath);
                        final pathLabel = isExternal ? 'External → ${videoPath.getLastSegments(segment: 1)}' : 'Local → ${videoPath.getLastPath()}';

                        return InkWell(
                          onHover: (isHover) => controller.onTopLargeHover(index, isHover),
                          onTap: () async {
                            final video = await DBVideos.getByVideoPath(videoPath);
                            if (video != null) await HomePanelVideoInfo.open(video);
                          },
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            decoration: BoxDecoration(
                              color: hoveredIndex == index ? Vx.neutral800.withValues(alpha: .6) : Colors.transparent,
                              border: Border(top: BorderSide(width: .5, color: Vx.neutral700)),
                            ),
                            child: Row(
                              children: [
                                _buildDataCell(
                                  '${item.videoCode.isNotEmptyAndNotNull ? item.videoCode : 'NON-JAV'}'
                                      .text
                                      .color(item.videoCode.isNotEmptyAndNotNull ? null : Vx.red300)
                                      .ellipsis
                                      .size(12)
                                      .make(),
                                  flex: 1,
                                ),
                                _buildDataCell(
                                  pathLabel.text.ellipsis.size(12).neutral400.make(),
                                  flex: 3,
                                ),
                                _buildDataCell(
                                  '${HelperMisc.formatVideoQuality(item.quality ?? '')}'.text.ellipsis.make().tooltip(item.quality ?? ''),
                                  flex: 1,
                                ),
                                _buildDataCell(
                                  '${item.filesize?.toFileSizeFormat()}'.text.ellipsis.make(),
                                  flex: 1,
                                  isLast: true,
                                ),
                              ],
                            ),
                          ),
                        );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).pOnly(left: 8);
  }
 
  Widget uiDuplicateVideo() {
    if (controller.duplicateVideoList.isEmpty) {
      return ExUiErrorOrEmpty(
        illustration: Icon(UIconsPro.regularRounded.flame, size: 128),
        title: '~ No Data Duplicate Found 🔥 ~',
      );
    }

    return VStack(
      [
        HStack([
          Obx(() => 'Total Duplicate: ${(controller.duplicateVideoList.length / 2).toInt()}'.text.make()),
          Spacer(),
        ]).pOnly(bottom: 12),
        Expanded(
          child: Obx(
            () => Table(
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
                    final rowColor = controller.duplicateHoveredIndex.value == index ? Vx.neutral800.withValues(alpha: .6) : Colors.transparent;
                    return TableRow(
                      children: [
                        MouseRegion(
                          onEnter: (_) => controller.onDuplicateHover(index, true),
                          onExit: (_) => controller.onDuplicateHover(index, false),
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            color: rowColor,
                            child: '${item.videoCode}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                              HomePanelVideoInfo.open(item);
                            }),
                          ),
                        ),
                        MouseRegion(
                          onEnter: (_) => controller.onDuplicateHover(index, true),
                          onExit: (_) => controller.onDuplicateHover(index, false),
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            color: rowColor,
                            child: (HelperMisc.isExternalDrive(item.videoPath)
                                    ? 'External → ${item.videoPath!.getLastSegments(segment: 1)}'
                                    : 'Local → ${item.videoPath!.getLastPath()}')
                                .text
                                .ellipsis
                                .size(12)
                                .neutral400
                                .make()
                                .p12()
                                .onInkTap(() async {
                              await HomePanelVideoInfo.open(item);
                            }),
                          ),
                        ),
                        MouseRegion(
                          onEnter: (_) => controller.onDuplicateHover(index, true),
                          onExit: (_) => controller.onDuplicateHover(index, false),
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            color: rowColor,
                            child: '${item.filesize?.toFileSizeFormat()}'.text.ellipsis.size(12).make().p12().onInkTap(() async {
                              await HomePanelVideoInfo.open(item);
                            }),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ).scrollVertical(),
          ),
        ),
      ],
    ).pOnly(left: 8);
  }

  Widget uiTODO() {
    if (controller.todoList.isEmpty) {
      return ExUiErrorOrEmpty(
        child: VStack([
          Icon(UIconsPro.regularRounded.to_do_alt, size: 128).pOnly(bottom: 16).centered(),
          'No Data TODO'.text.bold.makeCentered().pOnly(bottom: 2),
          'You can add todo by clicking the button below'.text.size(12).makeCentered().pOnly(bottom: 12),
          ExButtonText(
            label: 'Add New Todo',
            labelSize: 13,
            isLabelBold: true,
            onPressed: () => controller.addTodo(),
          ).tooltip('Add Todo: [⌘ + T]').centered(),
        ]).centered(),
      );
    }
    return VStack(
      [
        HStack([
          Obx(() => 'Total Todo: ${controller.todoList.length}'.text.make()),
          Spacer(),
          Tooltip(
            message: 'Add Todo: [⌘ + T]',
            child: IconButton(
              icon: Icon(UIconsPro.regularRounded.plus, size: 14),
              onPressed: () => controller.addTodo(),
            ),
          ),
        ]).pOnly(bottom: 12),
        Expanded(
          child: Obx(
            () => Table(
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
                    final rowColor = controller.todoHoveredIndex.value == index ? Vx.neutral800.withValues(alpha: .6) : Colors.transparent;
                    return TableRow(
                      children: [
                        MouseRegion(
                          onEnter: (_) => controller.onTodoHover(index, true),
                          onExit: (_) => controller.onTodoHover(index, false),
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            color: rowColor,
                            child: '${item.content}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                              final code = item.content?.replaceAll('✔︎', '').trim() ?? '';
                              if (code.isValidVideoCode()) {
                                var video = <String, dynamic>{};
                                video['video_code'] = code;
                                HelperOpener.openVideoInfo(video);
                              }
                            }),
                          ),
                        ),
                        MouseRegion(
                          onEnter: (_) => controller.onTodoHover(index, true),
                          onExit: (_) => controller.onTodoHover(index, false),
                          child: AnimatedContainer(
                            duration: 120.milliseconds,
                            color: rowColor,
                            child: HStack(
                              [
                                IconButton(
                                  icon: Icon(UIconsPro.regularRounded.trash, size: 14, color: Vx.neutral400),
                                  onPressed: () => controller.deleteTodos(controller.todoList[index]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ).scrollVertical(),
          ),
        ),
      ],
    ).pOnly(left: 8);
  }

  Widget uiAdvanceSearch() {
    return HStack([
      _buildLeftPart().pOnly(right: 12),
      _buildRightPart().expand(),
    ]).pOnly(left: 8);
  }

  Widget uiWatchNextQueue() {
    String fmtSeconds(num s) {
      final d = Duration(seconds: s.toInt());
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      if (h > 0) return '${h}h ${m}m';
      return '${d.inMinutes}m';
    }

    return VStack([
      HStack([
        'Queue Size'.text.size(12).make(),
        Obx(() => '(${controller.watchNextVideos.length})'.text.bold.size(12).make().pOnly(left: 6)),
        Spacer(),
        ExButtonText(label: 'Generate', labelSize: 12, onPressed: () => controller.generateWatchNextQueue()).pOnly(right: 8),
        ExButtonText(label: 'Play', labelSize: 12, onPressed: () => controller.playWatchNextQueue()),
      ]).pOnly(bottom: 12),
      HStack([
        Obx(() => Checkbox.adaptive(value: controller.watchNextPreferUnwatched.value, onChanged: (v) => controller.watchNextPreferUnwatched.value = v ?? true)),
        'Prefer Unwatched'.text.size(12).make(),
        16.widthBox,
        Obx(() => Checkbox.adaptive(value: controller.watchNextPreferRecent.value, onChanged: (v) => controller.watchNextPreferRecent.value = v ?? true)),
        'Prefer Recent'.text.size(12).make(),
        16.widthBox,
        'Random Mix'.text.size(12).make().pOnly(right: 8),
        Obx(
          () => Slider(
            min: 0,
            max: 1,
            value: controller.watchNextRandomMix.value,
            divisions: 10,
            label: controller.watchNextRandomMix.value.toStringAsFixed(2),
            onChanged: (v) => controller.watchNextRandomMix.value = v,
          ).w(140),
        ),
        16.widthBox,
        'Max'.text.size(12).make().pOnly(right: 8),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.minus, size: 13),
          onPressed: () => controller.watchNextMaxItems.value = (controller.watchNextMaxItems.value - 10).clamp(20, 500),
        ).w(28),
        Obx(() => '${controller.watchNextMaxItems.value}'.text.size(12).make().w(40)),
        IconButton(
          icon: Icon(UIconsPro.regularRounded.plus, size: 13),
          onPressed: () => controller.watchNextMaxItems.value = (controller.watchNextMaxItems.value + 10).clamp(20, 500),
        ).w(28),
      ]).pOnly(bottom: 12),
      Expanded(
        child: Obx(
          () => ListView.builder(
            itemCount: controller.watchNextVideos.length,
            itemBuilder: (context, i) {
              final item = controller.watchNextVideos[i];
              return Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(width: .4, color: Vx.neutral700))),
                child: HStack([
                  '${i + 1}'.text.size(11).neutral500.make().w(32),
                  '${item.videoCode}'.text.bold.size(12).ellipsis.make().w(120),
                  '${item.title}'.text.size(12).ellipsis.make().expand(),
                  '${fmtSeconds(item.duration ?? 0)}'.text.size(11).neutral400.make().pOnly(left: 8, right: 8),
                  IconButton(icon: Icon(UIconsPro.regularRounded.progress_complete, size: 13), onPressed: () => controller.markWatchNextDone(item)),
                  IconButton(icon: Icon(UIconsPro.regularRounded.cross, size: 13), onPressed: () => controller.skipWatchNext(item)),
                ]).pSymmetric(h: 8, v: 6),
              );
            },
          ),
        ),
      ),
    ]).pOnly(left: 8);
  }

  Widget uiHealthDashboard() {
    String fmtSec(dynamic value) {
      final s = (value as num?)?.toInt() ?? 0;
      final d = Duration(seconds: s);
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }

    Widget card(String label, String value, {Color? color}) {
      return Container(
        width: 220,
        padding: EdgeInsets.all(12),
        decoration: ExDecorator.box(borderColor: AppColor.border, fillColor: AppColor.container, borderRadius: 8),
        child: VStack([
          label.text.size(11).neutral400.make(),
          value.text.bold.size(16).color(color).make().pOnly(top: 6),
        ], crossAlignment: CrossAxisAlignment.start),
      ).pOnly(right: 12, bottom: 12);
    }

    return Obx(() {
      final h = controller.healthSummary;
      return VStack([
        HStack([
          ExButtonText(label: 'Refresh', labelSize: 12, onPressed: () => controller.refreshHealthDashboard()).pOnly(right: 8),
          Spacer(),
          'Updated: ${controller.healthLastUpdatedAt.value.isEmpty ? '-' : controller.healthLastUpdatedAt.value.reformatDate(to: 'yy/MM/dd HH:mm:ss')}'.text.size(11).neutral500.make(),
        ]).pOnly(bottom: 12),
        Wrap(
          children: [
            card('Total Video', '${h['totalVideo'] ?? 0}'),
            card('Duplicate Paths', '${h['duplicatePaths'] ?? 0}', color: Vx.orange300),
            card('Missing Files', '${h['missingFiles'] ?? 0}', color: Vx.red300),
            card('External Offline', '${h['externalOffline'] ?? 0}', color: Vx.red300),
            card('Missing Metadata', '${h['missingMetadata'] ?? 0}', color: Vx.amber300),
            card('Watch 7 Days', fmtSec(h['watchSeconds7d'])),
            card('Watch 30 Days', fmtSec(h['watchSeconds30d'])),
          ],
        ).expand(),
      ]).pOnly(left: 8);
    });
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────

  Widget _buildHeaderCell(String label, {required int flex, bool isLast = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: isLast ? BorderSide.none : BorderSide(width: .5, color: Vx.neutral700)),
        ),
        child: label.text.bold.size(12).make().pOnly(left: 8).pSymmetric(v: 6),
      ),
    );
  }

  Widget _buildDataCell(Widget child, {required int flex, bool isLast = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: isLast ? BorderSide.none : BorderSide(width: .5, color: Vx.neutral700)),
        ),
        child: child.p12(),
      ),
    );
  }

  Widget _buildLeftPart() {
    return Container(
      width: 220,
      height: Get.height,
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: VStack(
        [

          // filter by
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

          // search 
          CupertinoTextField(
            controller: controller.tecFilterSearchLeft,
            focusNode: controller.fnFilterSearchLeft,
            placeholder: 'Search (${controller.leftList.length})...',
            style: TextStyle(color: Vx.white, fontSize: 12),
            clearButtonMode: OverlayVisibilityMode.editing,
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            onSubmitted: (s) async => await controller.onLeftListDoSearch(s),
          ).pSymmetric(v: 16),
          
          // list
          FocusScope(
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
          illustration: Icon(CupertinoIcons.chevron_left_2, size: 64).pOnly(bottom: 12),
          message: 'Please select left area first',
        ),
      );
    }

    return Container(
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: controller.obx(
        (state) => VStack(
          [
            // header
            HStack([
              // 1
              CustomPopup(
                content: '${controller.leftListSelected}'.text.size(11).black.make().constrainedBox(BoxConstraints(maxWidth: 300)),
                child: HStack([
                  Icon(UIconsPro.solidRounded.info, size: 12).pOnly(right: 8),
                  'Result (${controller.rightListFiltered.length})'.text.minFontSize(11).size(11).make(),
                ]),
              ),

              Spacer(),

              // 2
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
            ]).pOnly(bottom: 12),

            // list video
            Obx(() => _buildVideoList()).expand(),

          ],
        ).p12(),
        onLoading: ExUiLoading(message: 'Loading...'.text.size(11).minFontSize(11).makeCentered()),
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
      itemCount: controller.rightListFiltered.length,
      itemBuilder: (context, i) {
        final item = controller.rightListFiltered[i];
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
              color: AppColor.black180,
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
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                '${item['release_date'].toString().reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).align(TextAlign.center).ellipsis.make(),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(left: 0),

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
