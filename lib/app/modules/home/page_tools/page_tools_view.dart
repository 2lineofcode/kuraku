import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper.dart';
import '../page_search/page_search_overlay.dart';
import 'page_tools_controller.dart';

class PageToolsView extends GetView<PageToolsController> {
  const PageToolsView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        // header
        ListView.builder(
          itemCount: controller.menus.length,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final item = controller.menus[index];
            return Obx(
              () => ExButtonOutline(
                label: item,
                labelSize: 12,
                labelColor: controller.toolSelected.value == item ? Vx.white : Vx.neutral500,
                borderColor: controller.toolSelected.value == item ? AppColor.selected : AppColor.container,
                backgroundColor: controller.toolSelected.value == item ? AppColor.selected : AppColor.container,
                onPressed: () => controller.onMenuChange(item),
              ).pOnly(right: 8),
            );
          },
        ).h(30).pOnly(bottom: 16),

        // content
        Obx(() {
          switch (controller.toolSelected.value) {
            case kDuplicate:
              return buildUIFindDuplicate().expand();
            case kTodo:
              return buildUITodo().expand();
            case kTopLargeFile:
              return buildUITopLargeFile().expand();
            default:
              return Container();
          }
        })
      ],
    );
  }

  Widget buildUIFindDuplicate() {
    return VStack(
      [
        HStack([
          Obx(() => 'Total Duplicate: ${controller.totalDupVideos}'.text.make()),
          Spacer(),
        ]).pOnly(bottom: 12),
        Table(
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
              ],
            ),
            ...List.generate(
              controller.dupVideos.length,
              (index) {
                final item = controller.dupVideos[index];
                return TableRow(
                children: [
                  // code
                  '${item.videoCode}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                    PageSearchOverlay.onItemTap(item);
                  }),
              
                  if (item.videoPath!.contains('/Volumes')) ...[
                    'External → ${item.videoPath!.toString().getLastSegments(segment: 1)}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                      await PageSearchOverlay.onItemTap(item);
                    }),
                  ] else ...[
                    'Local → ${item.videoPath!.toString().getLastPath()}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                      await PageSearchOverlay.onItemTap(item);
                    }),
                  ],
              
                ],
              );
              },
            ),
          ],
        ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }

  Widget buildUITodo() {
    return VStack(
      [
        HStack([
          Obx(() => 'Total Todo: ${controller.todos.length}'.text.make()),
          Spacer(),
          IconButton(
            icon: Icon(UIconsPro.regularRounded.plus, size: 14),
            onPressed: () => controller.addTodo(),
          ),
        ]).pOnly(bottom: 12),
        Table(
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
              controller.todos.length,
              (index) => TableRow(
                children: [
                  // code
                  '${controller.todos[index].message}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                    final isValidCode = HelperMisc.isValidVideoCode(controller.todos[index].message ?? '');
                    if (isValidCode) {
                      var item = <String, dynamic>{};
                      item['video_code'] = controller.todos[index].message;
                      HelperOpener.openVideoInfo(item);
                    }
                  }),

                  // action
                  HStack(
                    [
                      IconButton(
                        icon: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral400),
                        onPressed: () => controller.itemTodosSearch(controller.todos[index].message ?? ''),
                      ),
                      IconButton(
                        icon: Icon(UIconsPro.regularRounded.trash, size: 14, color: Vx.neutral400),
                        onPressed: () => controller.deleteTodos(controller.todos[index]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }

  Widget buildUITopLargeFile() {
    return VStack(
      [
        HStack([
          Obx(() => 'Top ${controller.top100LargeFile.length} Large File'.text.make()),
          Spacer(),
        ]).pOnly(bottom: 12),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(1),
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
              controller.top100LargeFile.length,
              (index) {
                var item = controller.top100LargeFile[index];
                return TableRow(
                children: [
                  // code
                  '${item['code']}'.text.ellipsis.size(12).make().p12().onInkTap(() async {
                    final video = await DBVideos.getByVideoPath(item['path'] ?? '');
                    await PageSearchOverlay.onItemTap(video[0]);
                  }),
              
                  // path
                  if (item['path']!.contains('/Volumes')) ...[
                    'External → ${item['path']!.toString().getLastSegments(segment: 1)}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                      final video = await DBVideos.getByVideoPath(item['path'] ?? '');
                      await PageSearchOverlay.onItemTap(video[0]);
                    }),
                  ] else ...[
                    'Local → ${item['path']!.toString().getLastPath()}'.text.ellipsis.size(12).neutral400.make().p12().onInkTap(() async {
                      final video = await DBVideos.getByVideoPath(item['path'] ?? '');
                      await PageSearchOverlay.onItemTap(video[0]);
                    }),
                  ],
              
                  // size
                  '${item['size']}'.text.ellipsis.make().p12(),
                ],
              );
              },
            ),
          ],
        ),
      ],
    ).pOnly(left: 8).scrollVertical();
  }
}
