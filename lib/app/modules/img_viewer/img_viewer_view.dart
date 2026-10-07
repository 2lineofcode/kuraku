import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import '../widgets/widget_controls.dart';
import '../widgets/widget_style.dart';
import '../widgets/widget_thumbnail.dart';
import 'img_viewer_controller.dart';

class ImgViewerView extends GetView<ImgViewerController> {
  const ImgViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final isMacOS = Platform.isMacOS;
    final macTopInset = MediaQuery.of(context).padding.top;
    final macTitleInset = isMacOS ? 0.0 : 0.0;
    final macBackInset = isMacOS ? 80.0 : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColor.appBar,
        toolbarHeight: 44,
        leadingWidth: isMacOS ? (52 + macBackInset) : 52,
        titleSpacing: isMacOS ? 4 : NavigationToolbar.kMiddleSpacing,
        actionsPadding: EdgeInsets.only(right: 4, left: isMacOS ? 8 : 0),
        toolbarTextStyle: const TextStyle(fontSize: 14),
        titleTextStyle: const TextStyle(fontSize: 14),
        iconTheme: const IconThemeData(size: AppStyle.iconSize),
        title: Padding(
          padding: EdgeInsets.only(left: macTitleInset),
          child: Obx(() {
            final counter = controller.images.isEmpty ? '' : '  ${controller.selectedIndex.value + 1}/${controller.images.length}';
            return Text('${controller.currentTitle}$counter', style: const TextStyle(fontSize: 14));
          }),
        ),
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: macBackInset),
            child: AppIconButton(tooltip: 'Back'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft02, size: AppStyle.iconSize), onPressed: () => Navigator.of(context).maybePop()),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isMacOS && macTopInset > 0 ? macTopInset * 0.35 : 0),
          child: const SizedBox.shrink(),
        ),
        actions: [
          _buildAppBarAction(
            tooltip: 'Shuffle'.tr,
            onPressed: controller.shuffleImages,
            icon: HugeIcons.strokeRoundedShuffle,
          ),
          _buildAppBarAction(
            tooltip: 'Rotate left'.tr,
            onPressed: controller.rotateCounterClockwise,
            icon: HugeIcons.strokeRoundedRotateTopLeft,
          ),
          _buildAppBarAction(
            tooltip: 'Rotate right'.tr,
            onPressed: controller.rotateClockwise,
            icon: HugeIcons.strokeRoundedRotateTopRight,
          ),

          16.widthBox,

          _buildAppBarAction(
            tooltip: 'Zoom out'.tr,
            onPressed: controller.zoomOut,
            icon: HugeIcons.strokeRoundedMinusSign,
          ),
          _buildAppBarAction(
            tooltip: 'Reset zoom'.tr,
            onPressed: controller.resetZoom,
            icon: HugeIcons.strokeRoundedFocus,
          ),
          _buildAppBarAction(
            tooltip: 'Zoom in'.tr,
            onPressed: controller.zoomIn,
            icon: HugeIcons.strokeRoundedAdd01,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Focus(
        autofocus: true,
        focusNode: controller.focusNode,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            controller.previous();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            controller.next();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.add) {
            controller.zoomIn();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
            controller.zoomOut();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.digit0) {
            controller.resetZoom();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.keyR) {
            controller.rotateClockwise();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.keyL) {
            controller.rotateCounterClockwise();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.keyQ) {
            Get.back();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Obx(() {
          if (controller.images.isEmpty) return _emptyView();

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Obx(
                        () => InteractiveViewer(
                          transformationController: controller.transformationController,
                          minScale: 0.6,
                          maxScale: 5,
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: controller.getCurrentQuarterTurns(),
                              child: _image(
                                controller.currentImage,
                                width: Get.width,
                                height: Get.height,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _navButton(
                      alignment: Alignment.centerLeft,
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      visible: controller.canGoPrevious,
                      onPressed: controller.previous,
                    ),
                    _navButton(
                      alignment: Alignment.centerRight,
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      visible: controller.canGoNext,
                      onPressed: controller.next,
                    ),
                  ],
                ),
              ),
              _thumbnailStrip(),
            ],
          );
        }),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Text(
        'No image found'.tr,
        style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 14),
      ),
    );
  }

  Widget _buildAppBarAction({
    required String tooltip,
    required VoidCallback onPressed,
    required List<List<dynamic>> icon,
  }) {
    return AppIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: HugeIcon(icon: icon, size: AppStyle.iconSize),
      iconSize: AppStyle.iconSize,
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(8),
    );
  }

  Widget _navButton({
    required Alignment alignment,
    required List<List<dynamic>> icon,
    required bool visible,
    required VoidCallback onPressed,
  }) {
    if (!visible) return const SizedBox.shrink();

    return Align(
      alignment: alignment,
      child: AppIconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(backgroundColor: AppColor.black120),
        iconSize: AppStyle.playbackIconSize,
        icon: HugeIcon(icon: icon, size: AppStyle.playbackIconSize),
      ).p12(),
    );
  }

  Widget _thumbnailStrip() {
    return Container(
      height: 84,
      color: AppColor.container,
      child: ListView.builder(
        controller: controller.thumbnailScrollController,
        padding: const EdgeInsets.all(6),
        scrollDirection: Axis.horizontal,
        itemCount: controller.images.length,
        itemBuilder: (context, index) {
          final image = controller.images[index];

          return Obx(() {
            final selected = controller.selectedIndex.value == index;

            return GestureDetector(
              onTap: () {
                controller.selectImage(index);
              },
              child: Container(
                width: 120,
                height: 72,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? AppColor.success : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _image(
                  image,
                  width: 116,
                  height: 68,
                  fit: BoxFit.contain,
                ),
              ),
            );
          });
        },
      ),
    );
  }

  Widget _image(
    String image, {
    required double width,
    required double height,
    required BoxFit fit,
  }) {
    final file = File(image);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _brokenImage(width, height),
      );
    }

    return ExThumbnail(
      imageUrl: image,
      videoPath: controller.videoPath.value,
      width: width,
      height: height,
      fitUrl: fit,
      backdropColor: Colors.black,
    );
  }

  Widget _brokenImage(double width, double height) {
    return HugeIcon(
      icon: HugeIcons.strokeRoundedImage01,
      color: Colors.white.withAlpha(160),
      size: AppStyle.emptyIconSize,
    ).wh(width, height);
  }
}
