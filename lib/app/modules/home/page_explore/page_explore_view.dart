import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../page_tools/page_tools_controller.dart';
import 'page_explore_controller.dart';

class PageExploreView extends GetView<PageExploreController> {
  const PageExploreView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => controller.isFresh.isFalse
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
        'Filter By'.text.size(12).make().pOnly(bottom: 16),
        ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: controller.menus.length,
          itemBuilder: (context, index) {
            return Obx(
              () => ExButtonOutline(
                label: controller.menus[index],
                labelSize: 12,
                labelColor: controller.currentMenuSelected.value == controller.menus[index] ? Vx.white : Vx.neutral500,
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
          Obx(
            () => CupertinoTextField(
              controller: controller.tecSearchLeft,
              focusNode: controller.fnSearchLeft,
              placeholder: controller.phSearchLeft.value,
              style: TextStyle(color: Vx.white, fontSize: 12),
              clearButtonMode: OverlayVisibilityMode.editing,
              prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
              onChanged: (s) => controller.onLeftListDoSearch(s),
            ).pSymmetric(v: 8),
          ),
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
                        itemCount: controller.leftListFiltered.length,
                        separatorBuilder: (context, index) => Divider(color: AppColor.border),
                        itemBuilder: (context, index) {
                          final item = controller.leftListFiltered[index];
                          return Obx(
                            () {
                              final isSelected = item == controller.leftListSelected.value;
                              final isHovered = index == controller.leftListHoveredIndex.value;

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
          () => controller.rightListLocal.isEmpty
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
              ]),
            ),
          ]).expand(),

          CupertinoTextField(
            controller: controller.tecSearchRight,
            focusNode: controller.fnSearchRight,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: controller.phSearchRight.value,
            style: TextStyle(color: Vx.white, fontSize: 14),
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            onChanged: (q) => controller.onRightListDoSearch(q),
          ).w(120).centered().pOnly(right: 12).hide(isVisible: controller.rightListViewMode.value == kR18),

        ],
      ).pSymmetric(h: 8),
    ).pOnly(bottom: 12);
  }

  Widget _buildVListLocal() {
    final double width = 160;
    final double height = 230;

    return GridView.builder(
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

        if (controller.currentMenuSelected.value == kCustom && controller.leftListSelected.value.name == '🟢 Star Rank') {
          return Container(
            color: AppColor.container,
            child: ZStack([
              ExAvatarView(
                source: item.fanArt ?? '',
                width: 90,
                height: 90,
              ).wh(90, 90).cornerRadius(90).centered().positioned(top: 55, left: 0, right: 0),
              '${item.title}'.text.makeCentered().positioned(bottom: 40, left: 0, right: 0),
              Container(
                color: AppColor.black180,
                width: width,
                height: 20,
                child: '${item.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
              ).positioned(bottom: 0, left: 0, right: 0),
            ]),
          ).onInkTap(() async {
            try {
              final _home = Get.find<HomeController>();
              final _tool = Get.find<PageToolsController>();

              final id = item.id.toInt();
              final name = '${item.title}';

              await _home.onMenuChange(kMenuTools);
              await _tool.onMenuChange(kAdvanceSearch);
              
              _tool.currentFilterBy.value = kActress;
              _tool.tecFilterSearchLeft.text = name;
              await _tool.onLeftListDoSearch(name);

              final _item = {'id': id, 'name_en': name};
              await _tool.onLeftListTap(_item, 0);
            } catch (_) {}
          });
        }

        return RepaintBoundary(
          child: DoubleTap(
            onSingleTap: () => controller.onRightListTap(item),
            onDoubleTap: () => HelperOpener.openVideoFile(item),
            child: Container(
              color: AppColor.container,
              child: ZStack([
                ExThumbnail(
                  imageUrl: item.fanArt,
                  videoPath: item.videoPath,
                  width: width,
                  height: height,
                  prefix: 2.12,
                ).wh(width, height),
            
                if (item.releaseDate != null && item.releaseDate != '' && controller.leftListSelected.value.name != 'Most Watch') ...[
                  '${item.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().pSymmetric(h: 4).wh(80, 17).color(AppColor.black180).positioned(),
                ],
            
                if (controller.currentMenuSelected.value == kCustom && controller.leftListSelected.value.name == 'Most Watch') ...[
                  'View: ${item.viewCount}'.text.size(10).minFontSize(10).make().pSymmetric(h: 4).wh(56, 17).color(AppColor.black180).positioned(),
                ],
            
                Container(
                  color: AppColor.black180,
                  width: width,
                  height: 20,
                  child: '${item.videoCode == '' ? item.title?.maxChars(10) : item.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
                ).positioned(bottom: 0, left: 0, right: 0),
            
                _buildFlagENSubOverlay(item),
                _buildFlagIDSubOverlay(item),
                _buildFlagUncensoredOverlay(item),
              ]),
            ).cornerRadius(8),
          ),
        );
      },
    );
  }

  Widget _buildVListR18() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 300 / 200,
      ),
      itemCount: controller.rightListR18Filtered.length,
      itemBuilder: (context, i) {
        final item = controller.rightListR18Filtered[i];
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
                width: 75,
                height: 18,
                child: '${item['release_date'].toString().reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).align(TextAlign.center).ellipsis.makeCentered(),
              ).positioned(left: 0),
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
    );
  }

  Widget _buildOverlayContainer({required Color color, required bool isVisible}) {
    return Container(
      color: color,
      width: 300,
      height: 200,
    ).hide(isVisible: isVisible);
  }

  Widget _buildFlagIDSubOverlay(Videos item) {
    if (item.videoPath?.isHasIdSub() == false) {
      return 0.heightBox;
    }
    return 'ID-SUB'.text.makeCentered().pSymmetric(h: 4).wh(double.infinity, 17).color(Vx.blue500.withAlpha(200)).positioned(bottom: 20, right: 0, left: 0);
  }

  Widget _buildFlagENSubOverlay(Videos item) {
    if (item.videoPath?.isHasEnSub() == false) {
      return 0.heightBox;
    }
    return 'EN-SUB'.text.makeCentered().pSymmetric(h: 4).wh(double.infinity, 17).color(Vx.purple500.withAlpha(150)).positioned(bottom: 20, right: 0, left: 0);
  }

  Widget _buildFlagUncensoredOverlay(Videos item) {
    if (item.videoPath?.isHasUncensored() == false) {
      return 0.heightBox;
    }
    return 'REDUCE MOSAIC'.text.makeCentered().pSymmetric(h: 4).wh(double.infinity, 17).color(Vx.red500.withAlpha(150)).positioned(bottom: 20, right: 0, left: 0);
  }
}
