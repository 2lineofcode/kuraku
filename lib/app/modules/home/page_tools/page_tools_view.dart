import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_media_stack.dart';
import '../../widgets/widget_thumbnail.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_video_info.dart';
import '../page_explore/page_explore_controller.dart';
import 'page_tools_controller.dart';

class PageToolsView extends GetView<PageToolsController> {
  const PageToolsView({super.key});
  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return VStack(
      [
        // header
        _buildMenu().h(30).pOnly(bottom: 16),

        buildResolutionScan(),

        // content
        Obx(() {
          switch (controller.currentMenuSelected.value) {
            case kTopLargeFile: return uiTopLargeFileSize().expand();
            case kDuplicate: return uiDuplicateVideo().expand();
            case kTodo: return uiTODO().expand();
            case kAdvanceSearch: return uiAdvanceSearch(context).expand();
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
            labelColor: controller.currentMenuSelected.value == item ? AppColor.text : AppColor.muted,
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
  Widget buildResolutionScan() => Obx(() {
    final running = controller.qualityScanRunning.value;
    final missing = controller.missingQualityCount.value;
    final status = controller.qualityScanStatus.value;
    final failed = status.startsWith('Scan failed');
    final stopping = status.startsWith('Stopping');
    if (!running && missing == 0 && !failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        if (running) ...[
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
            strokeWidth: 1.5,
            value: controller.qualityScanTotal.value == 0 ? null : controller.qualityScanChecked.value / controller.qualityScanTotal.value,
            semanticsLabel: 'Resolution scan progress',
          )),
          const SizedBox(width: 8),
          Expanded(child: Tooltip(
            message: '${controller.qualityScanFile.value}\n${controller.qualityScanUpdated.value} updated · ${controller.qualityScanSkipped.value} skipped',
            child: Text('Scanning ${controller.qualityScanChecked.value}/${controller.qualityScanTotal.value}', style: const TextStyle(fontSize: 11)),
          )),
        ],
        if (!running && (failed || controller.qualityScanSkipped.value > 0))
          Tooltip(message: status, child: const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.info_outline, size: 14),
          )),
        Tooltip(
          message: running ? 'Keep completed results' : 'Scan missing video resolutions',
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: stopping && running ? null : running ? controller.stopQualityScan : controller.scanAndUpdateDBVideoRes,
            child: Text(running ? stopping ? 'Stopping…' : 'Stop' : 'Scan ($missing)', style: const TextStyle(fontSize: 11)),
          ),
        ),
      ]),
    );
  });

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
                decoration: ExDecorator.box(borderColor: AppColor.border, fillColor: AppColor.container, borderRadius: 6),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: HStack(
                  [
                    Icon(UIconsPro.regularRounded.filter, size: 12).pOnly(right: 12),
                    Obx(
                      () => Text(
                        controller.topLargeFilterMode.value.isEmpty ? '<select>' : controller.topLargeFilterMode.value.toTitleCase!,
                        style: TextStyle(fontSize: 12, color: AppColor.text),
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
              border: Border.all(width: .5, color: AppColor.border)
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColor.container,
                    border: Border(
                      bottom: BorderSide(width: .5, color: AppColor.border)
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildHeaderCell('Thumbnail', flex: 1),
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
                              color: hoveredIndex == index ? AppColor.hover : Colors.transparent,
                              border: Border(top: BorderSide(width: .5, color: AppColor.border)),
                            ),
                            child: Row(
                              children: [
                                _buildDataCell(
                                  _buildMediaThumbnail(
                                    poster: item.poster ?? '',
                                    videoPath: videoPath,
                                    preferVideoPath: false,
                                  ),
                                  flex: 1,
                                ),
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
                                  pathLabel.text.ellipsis.size(12).color(AppColor.muted).make(),
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
    return VStack(
      [
        HStack([
          Obx(() => 'Duplicate Groups: ${controller.duplicateGroupCount.value} | Matched Videos: ${controller.duplicateVideoList.length}'.text.make()),
          Spacer(),
          Obx(
            () => HStack(
              controller.duplicateModes.map((mode) {
                final isSelected = controller.duplicateMode.value == mode;
                return ExButtonOutline(
                  label: mode == 'exact' ? 'Exact' : 'Probable',
                  labelSize: 11,
                  labelColor: isSelected ? AppColor.text : AppColor.muted,
                  borderColor: isSelected ? AppColor.selected : AppColor.container,
                  backgroundColor: isSelected ? AppColor.selected : AppColor.container,
                  onPressed: () => controller.setDuplicateMode(mode),
                ).pOnly(left: 8);
              }).toList(),
            ),
          ),
        ]).pOnly(bottom: 12),
        Obx(
          () => (
            controller.duplicateMode.value == 'exact'
                ? 'Exact = same code, atau non-JAV dengan filesize + normalized filename yang sama'
                : 'Probable = same normalized filename/title, cocok buat re-download beda resolusi'
          ).text.size(11).color(AppColor.muted).make().pOnly(bottom: 12),
        ),
        Expanded(
          child: Obx(
            () {
              if (controller.duplicateVideoList.isEmpty) {
                return ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.flame, size: 128),
                  title: controller.duplicateMode.value == 'exact'
                      ? '~ No Exact Duplicate Found 🔥 ~'
                      : '~ No Probable Duplicate Found 🔥 ~',
                );
              }

              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(4),
                },
                border: TableBorder.all(width: 0.5, color: AppColor.border),
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
                      final rowColor = controller.duplicateHoveredIndex.value == index ? AppColor.hover : Colors.transparent;
                      return TableRow(
                        children: [
                          MouseRegion(
                            onEnter: (_) => controller.onDuplicateHover(index, true),
                            onExit: (_) => controller.onDuplicateHover(index, false),
                            child: AnimatedContainer(
                              duration: 120.milliseconds,
                              color: rowColor,
                              child: '${item.videoCode.isNotEmptyAndNotNull ? item.videoCode : item.title.isNotEmptyAndNotNull ? item.title : 'NON-JAV'}'
                                  .text
                                  .color(item.videoCode.isNotEmptyAndNotNull ? null : Vx.red300)
                                  .ellipsis
                                  .size(12)
                                  .make()
                                  .p12()
                                  .onInkTap(() {
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
                                  .color(AppColor.muted)
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
              ).scrollVertical();
            },
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
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(width: .5, color: AppColor.border),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColor.container,
                    border: Border(
                      bottom: BorderSide(width: .5, color: AppColor.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildHeaderCell('Thumbnail', flex: 1),
                      _buildHeaderCell('Todo', flex: 4),
                      _buildHeaderCell('Action', flex: 1, isLast: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Obx(
                    () {
                      final hoveredIndex = controller.todoHoveredIndex.value;
                      return ListView.builder(
                        itemCount: controller.todoList.length,
                        itemBuilder: (context, index) {
                          final item = controller.todoList[index];
                          final todoText = item.content ?? '';
                          final code = todoText.replaceAll('✔︎', '').trim();

                          return InkWell(
                            onHover: (isHover) => controller.onTodoHover(index, isHover),
                            onTap: () {
                              if (!code.isValidVideoCode()) return;
                              final video = <String, dynamic>{'video_code': code};
                              HelperOpener.openVideoInfo(video);
                            },
                            child: AnimatedContainer(
                              duration: 120.milliseconds,
                              decoration: BoxDecoration(
                                color: hoveredIndex == index ? AppColor.hover : Colors.transparent,
                                border: Border(top: BorderSide(width: .5, color: AppColor.border)),
                              ),
                              child: Row(
                                children: [
                                  _buildDataCell(_buildTodoThumbnail(todoText), flex: 1),
                                  _buildDataCell(todoText.text.ellipsis.size(12).make(), flex: 4),
                                  _buildDataCell(
                                    IconButton(
                                      icon: Icon(UIconsPro.regularRounded.trash, size: 14, color: AppColor.muted),
                                      onPressed: () => controller.deleteTodos(item),
                                    ).centered(),
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

  Widget _buildTodoThumbnail(String? todoContent) {
    final code = (todoContent ?? '').replaceAll('✔︎', '').trim();
    if (!code.isValidVideoCode()) {
      return Icon(Icons.image_not_supported, size: 18, color: Vx.neutral500).centered();
    }

    final poster = controller.todoPosterByCode[code] ?? '';
    if (poster.isEmpty) {
      return Icon(Icons.broken_image, size: 18, color: Vx.neutral500).centered();
    }

    return _buildMediaThumbnail(poster: poster);
  }

  Widget _buildMediaThumbnail({String poster = '', String videoPath = '', bool preferVideoPath = false}) {
    final hasPoster = poster.trim().isNotEmpty;
    final hasVideoPath = videoPath.trim().isNotEmpty;
    final useVideoPath = hasVideoPath && (preferVideoPath || !hasPoster);

    if (!hasPoster && !hasVideoPath) {
      return Icon(Icons.broken_image, size: 18, color: Vx.neutral500).centered();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ExThumbnail(
        imageUrl: useVideoPath ? '' : poster,
        videoPath: useVideoPath ? videoPath : '',
        width: 80,
        height: 100,
        prefix: 1.9,
      ),
    ).centered();
  }

  Widget uiAdvanceSearch(BuildContext context) {
    return HStack([
      _buildLeftPart(context).pOnly(right: 12),
      _buildRightPart().expand(),
    ]).pOnly(left: 8);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────

  Widget _buildHeaderCell(String label, {required int flex, bool isLast = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: isLast ? BorderSide.none : BorderSide(width: .5, color: AppColor.border)),
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
          border: Border(right: isLast ? BorderSide.none : BorderSide(width: .5, color: AppColor.border)),
        ),
        child: child.p12(),
      ),
    );
  }

  Widget _buildLeftPart(BuildContext context) {
    final rowHeight = 84 * MediaQuery.textScalerOf(context).scale(12) / 12;
    return Container(
      width: 220,
      height: Get.height,
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: VStack(
        [

          // filter by
          HStack([
            'Browse'.text.size(12).bold.make().expand(),
            PopupMenuButton<String>(
              tooltip: 'Browse catalog by',
              initialValue: controller.currentFilterBy.value,
              onSelected: (kind) {
                switch (kind) {
                  case kActress: controller.filterByActress(); break;
                  case kSeries: controller.filterBySeries(); break;
                  case kCategory: controller.filterByCategories(); break;
                  case kYear: controller.filterByYear(); break;
                }
              },
              itemBuilder: (_) => [for (final kind in [kActress, kSeries, kCategory, kYear])
                PopupMenuItem(value: kind, child: Text(kind, style: const TextStyle(fontSize: 12))),
              ],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(controller.currentFilterBy.value, style: const TextStyle(fontSize: 11)),
                const Icon(Icons.expand_more, size: 16),
              ]).pSymmetric(h: 8, v: 4).box.color(AppColor.selected).make().cornerRadius(4),
            ),
          ]),

          // search 
          CupertinoTextField(
            controller: controller.tecFilterSearchLeft,
            focusNode: controller.fnFilterSearchLeft,
            placeholder: 'Search ${controller.currentFilterBy.value.toLowerCase()}...',
            style: TextStyle(color: AppColor.text, fontSize: 12),
            clearButtonMode: OverlayVisibilityMode.editing,
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            onChanged: controller.searchAdvancedGroups,
            onSubmitted: (s) async => await controller.onLeftListDoSearch(s),
          ).pSymmetric(v: 12),
          '${controller.leftList.length} items · ↑ ↓ to browse'.text.size(10).color(AppColor.muted).make().pOnly(bottom: 8),
          
          if (controller.leftListLoading.value) const LinearProgressIndicator(minHeight: 2),
          if (controller.leftListError.value.isNotEmpty) Column(children: [
            Text(controller.leftListError.value, style: const TextStyle(fontSize: 11)),
            TextButton(onPressed: () => controller.onLeftListDoSearch(controller.tecFilterSearchLeft.text), child: const Text('Retry')),
          ]),
          if (!controller.leftListLoading.value && controller.leftListError.value.isEmpty && controller.leftList.isEmpty)
            'No matching items'.text.size(11).color(AppColor.muted).make().p8(),
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
                delegate: FlutterListViewDelegate((context, index) {
                    final item = controller.leftList[index];
                    return SizedBox(
                      height: rowHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Expanded(child: Obx(
                          () {
                            final isSelected = '${item['id']}' == controller.leftListSelectedId.value;
                            final isHovered = index == controller.leftListHoveredIndex.value;
                            return MouseRegion(
                              onEnter: (_) => controller.leftListHoveredIndex.value = index,
                              onExit: (_) => controller.leftListHoveredIndex.value = -1,
                              child: InkWell(
                                onTap: () async => await controller.onLeftListTap(item, index),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(HelperDecensor.decensor(item['name_en']), style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if ((item['name_ja'] ?? '').toString().trim().isNotEmpty && item['name_ja'] != item['name_en'])
                                    Text('${item['name_ja']}', style: TextStyle(fontSize: 10, color: AppColor.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('${item['video_count']} videos · ${item['max_release_date'] ?? 'Date unknown'}', style: TextStyle(fontSize: 9, color: AppColor.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]).w(double.infinity).p4(),
                              )
                                  .color(isSelected ? AppColor.selected : isHovered ? AppColor.border : Colors.transparent)
                                  .cornerRadius(8),
                            );
                          },
                        )),
                        Divider(color: AppColor.border, thickness: 0.5, height: 8),
                      ],
                      ),
                    );
                },
                  childCount: controller.leftList.length,
                  onItemKey: (index) => '${controller.currentFilterBy.value}:${controller.leftList[index]['id']}',
                  onItemHeight: (_) => rowHeight,
                  preferItemHeight: rowHeight,
                  disableCacheItems: true,
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
          message: 'Choose an actress, series, category or year to browse the R18 catalog.',
        ),
      );
    }

    return Container(
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: controller.obx(
        (state) => Obx(() => VStack(
          [
            // header
            HStack([
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(HelperDecensor.decensor(controller.leftListSelected.value), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${controller.rightListFiltered.length} of ${controller.rightList.length} videos', style: TextStyle(fontSize: 10, color: AppColor.muted)),
              ])),
              if (controller.hasAdvancedFilters) TextButton(
                onPressed: controller.clearAdvancedFilters,
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),

              // 2
              Obx(
                () => ZStack([
                  IconButton(
                    tooltip: 'More filters: video code, year and duration',
                    icon: Icon(
                      controller.filter.isFiltered.isTrue ? UIconsPro.boldRounded.filter_list : UIconsPro.regularRounded.filter_list,
                      size: controller.filter.isFiltered.isTrue ? 16 : 14,
                    ),
                    onPressed: () => controller.openDialogFilter(),
                  ).pOnly(left: 8),
                  controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
                ]),
              ),
            ]).pOnly(bottom: 8),
            CupertinoTextField(
              controller: controller.tecResultSearch,
              placeholder: 'Search video code or title...',
              style: TextStyle(fontSize: 12, color: AppColor.text),
              clearButtonMode: OverlayVisibilityMode.editing,
              prefix: Icon(Icons.search, size: 16, color: AppColor.muted).pOnly(left: 8),
              onChanged: (value) {
                controller.resultQuery.value = value;
                controller.applyAdvancedFilters();
              },
            ).pOnly(bottom: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _advancedOption('Release', controller.releaseFilter.value, {'all': 'All dates', 'released': 'Released', 'upcoming': 'Upcoming'}, (value) => controller.releaseFilter.value = value),
              _advancedOption('Library', controller.libraryFilter.value, {'all': 'All videos', 'owned': 'In Library', 'missing': 'Not in Library'}, (value) => controller.libraryFilter.value = value),
              _advancedOption('Sort', controller.resultSort.value, {'newest': 'Newest released', 'oldest': 'Oldest', 'code': 'Video code'}, (value) => controller.resultSort.value = value),
            ]).pOnly(bottom: 12),

            // list video
            Obx(() => controller.rightListFiltered.isEmpty
                ? const Center(child: Text('No videos match the current filters'))
                : _buildVideoList()).expand(),

          ],
        ).p12()),
        onLoading: ExUiLoading(message: 'Loading...'.text.size(11).minFontSize(11).makeCentered()),
        onError: (error) => Center(child: Text(error ?? 'Could not load videos')),
        onEmpty: ExUiErrorOrEmpty(
          illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
          title: 'No Data Found',
          message: 'No Result Found, as you searched for "${controller.leftListSelected}"',
        ),
      ),
    );
  }

  Widget _advancedOption(String label, String selected, Map<String, String> options, void Function(String) onSelected) {
    return PopupMenuButton<String>(
      tooltip: label,
      initialValue: selected,
      onSelected: (value) {
        onSelected(value);
        controller.applyAdvancedFilters();
      },
      itemBuilder: (_) => options.entries.map((item) => PopupMenuItem(
        value: item.key, child: Text(item.value, style: const TextStyle(fontSize: 12)),
      )).toList(),
      child: Container(
        decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(options[selected]!, style: const TextStyle(fontSize: 11)),
          const Icon(Icons.expand_more, size: 14),
        ]),
      ),
    );
  }

  Widget _buildVideoList() {
    return GridView.builder(
      key: ValueKey(controller.leftListSelectedId.value),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
      ),
      itemCount: controller.rightListFiltered.length,
      itemBuilder: (context, i) {
        final item = controller.rightListFiltered[i];
        final date = DateTime.tryParse('${item['release_date'] ?? ''}')?.toIso8601String().substring(0, 10) ?? 'Date unknown';
        return LayoutBuilder(builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MediaStack([
            ExThumbnail(
              imageUrl: item['fan_art'] ?? '',
              videoCode: item['video_code'],
              width: constraints.maxWidth,
              height: 200,
              fitUrl: BoxFit.cover,
            ),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(
              color: AppColor.black180,
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item['video_code']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)).onInkTap(() {
                  HelperMisc.copyToClipboard(item['video_code'], showToast: true);
                }).tooltip('Copy video code'),
                if ('${item['title'] ?? ''}'.trim().isNotEmpty)
                  Text(HelperDecensor.decensor(item['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
              ]),
            )),
            Positioned(top: 6, left: 6, child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (constraints.maxWidth - 48).clamp(0, double.infinity)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(date, style: const TextStyle(fontSize: 10)).p4().color(AppColor.black180).cornerRadius(4),
                if (item['is_released'] == false)
                  const Text('Upcoming', style: TextStyle(fontSize: 10)).p4().color(Colors.brown.shade800).cornerRadius(4).pOnly(top: 4),
                if (item['match'] == true)
                  const Text('In Library', style: TextStyle(fontSize: 10)).p4().color(Colors.green.shade800).cornerRadius(4).pOnly(top: 4),
                if (Get.isRegistered<HomeController>()) GetBuilder<HomeController>(builder: (_) => item['is_clicked'] == true
                    ? const Text('Requested', style: TextStyle(fontSize: 10)).p4().color(Colors.blue.shade800).cornerRadius(4).pOnly(top: 4)
                    : const SizedBox.shrink()),
              ]),
            )),
            Positioned(right: 6, top: 6, child: Column(children: [
              IconButton(
                tooltip: 'Open trailer',
                style: IconButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                onPressed: () => HelperOpener.openTrailer(item),
              ),
              const SizedBox(height: 4),
              IconButton(
                tooltip: 'Open screenshots',
                style: IconButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const Icon(Icons.photo_outlined, size: 16),
                onPressed: () => HelperOpener.openScreenshot(item),
              ),
            ])),
          ]).onInkTap(() async => await HelperOpener.openVideoInfo(item)),
        ));
      },
    );
  }
}
