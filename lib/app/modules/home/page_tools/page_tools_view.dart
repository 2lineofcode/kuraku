import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:flutter_popup/flutter_popup.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
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
    return HStack(
      [
        // r1
        Container(
          width: 220,
          height: Get.height,
          decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
          child: VStack(
            [
              HStack([
                'Filter by: (${controller.listFilter.length})'.text.size(11).minFontSize(11).make(),
                Spacer(),
                Obx(
                  () => CustomPopup(
                    content: VStack([
                      // Actress
                      '${controller.filterBy.value == kActress ? '◉' : '◎'} $kActress'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                        controller.filterBy.value = kActress;
                        await controller.filterByActress();
                        Get.back();
                      }),

                      // Series
                      '${controller.filterBy.value == kSeries ? '◉' : '◎'} $kSeries'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                        controller.filterBy.value = kSeries;
                        await controller.filterBySeries();
                        Get.back();
                      }),

                      // Category
                      '${controller.filterBy.value == kCategory ? '◉' : '◎'} $kCategory'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                        controller.filterBy.value = kCategory;
                        await controller.filterByCategories();
                        Get.back();
                      }),

                      // Year
                      '${controller.filterBy.value == kYear ? '◉' : '◎'} $kYear'.text.minFontSize(11).size(11).black.make().p(4).onInkTap(() async {
                        controller.filterBy.value = kYear;
                        await controller.filterByYear();
                        Get.back();
                      }),
                    ]),
                    child: '${controller.filterBy}'.text.minFontSize(11).size(11).make().pSymmetric(h: 8).box.color(AppColor.selected).make().cornerRadius(4),
                  ),
                ),
              ]),
              CupertinoTextField(
                controller: controller.tecFilterSearch,
                focusNode: controller.fnFilterSearch,
                placeholder: 'Search (${controller.listFilter.length})...',
                style: TextStyle(color: Vx.white, fontSize: 12),
                clearButtonMode: OverlayVisibilityMode.editing,
                prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
                onSubmitted: (s) {
                  switch (controller.filterBy.value) {
                    case kActress: controller.filterByActress(q: s); break;
                    case kSeries: controller.filterBySeries(q: s); break;
                    case kCategory: controller.filterByCategories(q: s); break;
                    case kYear: controller.filterByYear(q: s); break;
                  }
                  controller.fnFilterSearch.requestFocus();
                  controller.listFilterScrollController.value.animToTop();
                },
              ).pSymmetric(v: 16),
              FlutterListView(
                controller: controller.listFilterScrollController.value,
                delegate: FlutterListViewDelegate(
                  (context, index) {
                    final item = controller.listFilter[index];
                    return VStack(
                      [
                        Obx(
                          () => InkWell(
                            onTap: () async => await controller.onFilterItemSelected(item),
                            child: '${item['name_en']}'.text.size(11).minFontSize(11).make().w(double.infinity).p4(),
                          ).color(item['name_en'] == controller.filterItemSelected.value ? AppColor.selected : Colors.transparent).cornerRadius(2),
                        ),
                        Divider(color: AppColor.border, thickness: 0.5),
                      ],
                    );
                  },
                  childCount: controller.listFilter.length,
                ),
              ).expand(),
            ],
          ).p12(),
        ).pOnly(right: 12),

        // r2
        Container(
          decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
          child: controller.obx(
            (state) => VStack(
              [
                'Result (${controller.r18ListVideo.length})'.text.minFontSize(11).size(11).make().pOnly(bottom: 12),
                vListR18().expand(),
              ],
            ).p12(),
            onLoading: ExUiLoading(
              message: 'Loading...'.text.size(11).minFontSize(11).makeCentered(),
            ),
            onEmpty: ExUiErrorOrEmpty(
              illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
              title: 'No Data Found',
              message: 'No Result Found, as you searched for "${controller.filterItemSelected}"',
            ),
          ),
        ).expand(),
      ],
    ).pOnly(left: 8);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~
  // ────────────────────────────────────────────────────────────────
  Widget vListR18() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.r18ListVideo.length,
      itemBuilder: (context, i) {
        final item = controller.r18ListVideo[i];
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

            // ** is_released (false)
            Container(
              color: Colors.red.withAlpha(70),
              width: 300,
              height: 200,
            ).hide(isVisible: item['is_released'] == false),

            // ** has Clicked
            GetBuilder(
              init: HomeController(),
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
              height: item['title'] != null && item['title'] != '' ? 62 : 33,
              child: VStack([
                '${item['video_code']}'.text.bold.size(12).ellipsis.make().onInkTap((){
                  HelperMisc.copyToClipboard(item['video_code'], showToast: true);
                }),
                '${HelperMisc.decodeHtml(item['title'] ?? '')}'.text.size(10).maxLines(2).minFontSize(10).ellipsis.make().w(240).hide(isVisible: item['title'] != null && item['title'] != ''),
              ]).p8(),
            ).positioned(bottom: 0, left: 0, right: 0),

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
    );
  }
}
