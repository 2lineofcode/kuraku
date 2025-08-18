import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
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
            case kAdvanceSearch:
              return buildUIAdvanceSearch().expand();
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
              (index) {
                final item = controller.todos[index];
                return TableRow(
                  children: [
                    // code
                    '${item.message}'.text.ellipsis.size(12).make().p12().onInkTap(() {
                      final code = item.message?.replaceAll('✔︎', '').trim() ?? '';
                      final isValidCode = HelperMisc.isValidVideoCode(code);
                      if (isValidCode) {
                        var video = <String, dynamic>{};
                        video['video_code'] = code;
                        HelperOpener.openVideoInfo(video);
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
                );
              },
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

  Widget buildUIAdvanceSearch() {
    return VStack(
      [
        Container(
          decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 2),
          child: HStack(
            [
              // r1
              VStack(
                [
                  HStack(
                    [
                      CupertinoTextField(
                        controller: controller.tecVideoCode,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        placeholder: 'Video Code..',
                        style: TextStyle(color: Vx.white, fontSize: 14),
                      ).expand(),
                      12.widthBox,
                      ExAutoComplate(
                        controller: controller.tecActressName,
                        items: controller.actresses,
                        placeHolder: 'Actress Name (${controller.actresses.length})',
                        onSelected: (s) => controller.tecActressName.text = s,
                      ).expand(),
                    ],
                  ),
                  8.heightBox,
                  Obx(
                    () => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: controller.categoriesSelected.map((tag) {
                        return Chip(
                          label: Text(tag, style: TextStyle(fontSize: 9)),
                          deleteIcon: Icon(Icons.close, size: 12),
                          labelPadding: EdgeInsets.all(2),
                          side: BorderSide(color: AppColor.container),
                          backgroundColor: AppColor.selected,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1)),
                          onDeleted: () => {
                            controller.categoriesSelected.remove(tag),
                          },
                        );
                      }).toList(),
                    ).pOnly(bottom: 12),
                  ),
                  ExAutoComplate(
                    controller: controller.tecCategory,
                    items: controller.categories,
                    placeHolder: 'Add Category (${controller.categories.length})',
                    emptyText: 'No Category with `${controller.tecCategory.text}` Found ',
                    onSelected: (s) {
                      controller.tecCategory.clear();
                      if (controller.categoriesSelected.contains(s)) return;
                      controller.categoriesSelected.add(s);
                    },
                  ).pOnly(bottom: 12),
                  HStack(
                    [
                      'Year:'.text.size(11).make().pOnly(right: 24),
                      Obx(
                        () => SliderTheme(
                          data: SliderTheme.of(Get.context!).copyWith(
                            trackHeight: 4,
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: AppColor.selected,
                            inactiveTrackColor: AppColor.container,
                            rangeTrackShape: RectangularRangeSliderTrackShape(),
                            valueIndicatorTextStyle: const TextStyle(fontSize: 10, color: Colors.white),
                            valueIndicatorColor: AppColor.container,
                            rangeThumbShape: RoundRangeSliderThumbShape(
                              enabledThumbRadius: 6,
                              disabledThumbRadius: 0,
                            ),
                          ),
                          child: RangeSlider(
                            values: controller.currentRange.value,
                            min: 2000,
                            max: DateTime.now().year.toDouble(),
                            divisions: (DateTime.now().year.toDouble() - 2000).toInt(),
                            labels: RangeLabels(
                              controller.currentRange.value.start.toInt().toString(),
                              controller.currentRange.value.end.toInt().toString(),
                            ),
                            onChanged: (RangeValues values) {
                              controller.currentRange.value = values;
                            },
                          ),
                        ).expand(),
                      ),
                      '${controller.currentRange.value.start.toInt()} - ${controller.currentRange.value.end.toInt()}'.text.size(11).make().pOnly(left: 24),
                    ],
                  ),
                ],
              ).expand(),

              // r2
              ExButtonElevated(
                label: 'Search',
                onPressed: () => controller.onAdvanceSearch(),
              ).pOnly(left: 12)
            ],
          ).p12(),
        ).pOnly(bottom: 12),
        'Result: ${controller.videos.length}'.text.size(11).make().pOnly(bottom: 8),
        modeGridView().expand(),
      ],
    );
  }

  Widget modeGridView() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.videos.length,
      itemBuilder: (context, i) {
        final item = controller.videos[i];
        return ZStack(
          [
            ExThumbnail(
              imageUrl: item['fan_art'] ?? '',
              width: 300,
              height: 200,
            ).wh(300, 200).cornerRadius(8),

            // ** match (already have )
            Container(
              color: Colors.green.withAlpha(100),
              width: 300,
              height: 200,
            ).hide(isVisible: item['match'] == true),

            // ** has Clicked
            GetBuilder(
              init: PageToolsController(),
              builder: (controller) {
                return Container(
                  color: Colors.blue.withAlpha(100),
                  width: 300,
                  height: 200,
                ).hide(isVisible: item['is_clicked'] == true);
              },
            ),

            Container(
              color: Vx.black.withAlpha(150),
              width: 300,
              height: 20,
              child: '${item['video_code']}'.text.bold.ellipsis.make().pOnly(left: 8),
            ).onInkTap(() async {
              HelperMisc.copyToClipboard(item['video_code'], showToast: true);
            }).positioned(bottom: 0),

            Container(
              color: Vx.black.withAlpha(150),
              width: 70,
              height: 18,
              child: '${item['release_date']}'.text.size(9).minFontSize(9).align(TextAlign.center).ellipsis.makeCentered(),
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
    ).wh(double.infinity, 100);
  }
}
