import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import 'page_search_controller.dart';
import 'page_search_overlay.dart';

class PageSearchView extends GetView<PageSearchController> {
  const PageSearchView({super.key});

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
        HStack([
          CupertinoTextField(
            controller: controller.tecSearch,
            focusNode: controller.fnSearch,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: '${controller.phSearch}',
            style: TextStyle(color: Vx.white, fontSize: 14),
            prefix: Icon(UIconsPro.regularRounded.search, size: 14, color: Vx.neutral500).pOnly(left: 8),
            onSubmitted: (value) => controller.onSearch(),
          ).expand(),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.regularRounded.apps, size: 14, color: controller.viewModeSelected.value == 'grid' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = kGrid,
            ),
          ),
          Obx(
            () => IconButton(
              icon: Icon(UIconsPro.regularRounded.list_timeline, size: 14, color: controller.viewModeSelected.value == 'list' ? Vx.white : Vx.neutral600),
              onPressed: () => controller.viewModeSelected.value = kList,
            ),
          ),
        ]).pOnly(bottom: 24),
        Obx(
          () => controller.isSearchMode.isTrue ? 'Result: ${controller.videos.length} Videos'.text.size(12).make().pOnly(bottom: 16) : 0.heightBox,
        ),
        Obx(
          () => controller.videos.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt, size: 32),
                  title: 'No Data Found',
                  message: 'No Result Found, as you searched for "${controller.tecSearch.text}"\nor Add some video to your library first.',
                ).expand()
              : controller.viewModeSelected.value == kGrid
                  ? modeGridView().expand()
                  : modeListView().expand(),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget modeListView() {
    return ListView.separated(
      controller: controller.scrollListController,
      itemCount: controller.videos.length,
      separatorBuilder: (context, index) => 12.heightBox,
      itemBuilder: (context, index) {
        final item = controller.videos[index];
        return DoubleTap(
          onSingleTap: () => PageSearchOverlay.onItemTap(item),
          onDoubleTap: () => HelperOpener.openVideoFile(item),
          child: Container(
            color: AppColor.container,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ZStack([
                  ExThumbnail(
                  imageUrl: item.fanArt,
                  videoPath: item.videoPath,
                  width: 250,
                  height: 150,
                  fitUrl: BoxFit.cover,
                ).pOnly(right: 12),
                _buildReleaseDateOverlay(item),
          
                ]),
                VStack([
                  '${item.videoCode == '' ? item.title?.maxWords(5) : item.videoCode}'.text.bold.ellipsis.make().pSymmetric(v: 8),
                  '${HelperDecensor.decensor(item.title)}'.text.size(12).maxLines(3).ellipsis.make(),
                  Spacer(),
                  HStack([
                    if (item.quality != '') ...[
                      Icon(UIconsPro.regularRounded.hdd, size: 12, color: Vx.amber300).pOnly(right: 6),
                      '${HelperMisc.formatVideoQuality(item.quality ?? '').maxWords(1)}'.text.amber300.size(12).minFontSize(12).make().pOnly(right: 12),
                    ],
                    if (item.filesize != 0) ...[
                      Icon(UIconsPro.regularRounded.file, size: 12).pOnly(right: 6),
                      '${item.filesize?.toFileSize()}'.text.size(12).maxLines(1).ellipsis.minFontSize(12).make().pOnly(right: 12).expand(),
                    ],
                  ]).pOnly(bottom: 4),
                  HStack(
                    [
                      if (item.series != '') ...[
                        Icon(UIconsPro.regularRounded.tags, size: 12, color: Vx.purple300).pOnly(right: 6),
                        '${HelperDecensor.decensor(item.series)}'.text.purple300.size(12).minFontSize(12).maxLines(1).ellipsis.make().pOnly(right: 12).expand(),
                      ],
                    ],
                  ).pOnly(bottom: 4),
                ]).pOnly(right: 12).expand(),
              ],
            ),
          ).wh(250, 150).cornerRadius(8),
        );
      },
    );
  }

  Widget modeGridView() {
    double width = 150;
    double height = 230;

    return GridView.builder(
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
          child: DoubleTap(
            onSingleTap: () => PageSearchOverlay.onItemTap(item),
            onDoubleTap: () => HelperOpener.openVideoFile(item),
            child: Container(
              color: AppColor.container,
              child: ZStack([
                ExThumbnail(
                  imageUrl: item.fanArt,
                  videoPath: item.videoPath,
                  width: width,
                  height: height,
                  prefix: 2.1,
                ).wh(width, height),
                _buildReleaseDateOverlay(item),
                _buildVideoCodeOverlay(item, width),
                _buildFlagIDSubOverlay(item),
                _buildFlagENSubOverlay(item),
                _buildFlagUncensoredOverlay(item),
              ]),
            ).cornerRadius(8),
          ),
        );
      },
    );
  }

  /// Builds the video title overlay with a dark background.
  Widget _buildVideoCodeOverlay(Videos item, double width) {
    return Container(
      color: AppColor.black180,
      width: width,
      height: 20,
      child: '${item.videoCode == '' ? item.title?.maxChars(10) : item.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
    ).positioned(bottom: 0, right: 0, left: 0);
  }

  /// Builds the release date overlay.
  Widget _buildReleaseDateOverlay(Videos item) {
    if (item.releaseDate == null || item.releaseDate!.isEmpty) {
      return 0.heightBox;
    }

    return '${item.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().pSymmetric(h: 4).wh(80, 17).color(AppColor.black180).positioned();
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
