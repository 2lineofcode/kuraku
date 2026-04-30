import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';

import '../../core/app_color.dart';
import '../widgets/widget_thumbnail.dart';
import 'img_viewer_controller.dart';

class ImgViewerView extends GetView<ImgViewerController> {
  const ImgViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColor.appBar,
        title: Obx(() {
          final title = controller.title.value.isEmpty ? 'Image Viewer' : controller.title.value;
          final counter = controller.images.isEmpty ? '' : '  ${controller.selectedIndex.value + 1}/${controller.images.length}';
          return Text('$title$counter', style: const TextStyle(fontSize: 14));
        }),
        actions: [
          IconButton(
            tooltip: 'Zoom out',
            onPressed: controller.zoomOut,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Reset zoom',
            onPressed: controller.resetZoom,
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: controller.zoomIn,
            icon: const Icon(Icons.add),
          ),
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
                      child: InteractiveViewer(
                        transformationController: controller.transformationController,
                        minScale: 0.6,
                        maxScale: 5,
                        child: Center(
                          child: _image(
                            controller.currentImage,
                            width: Get.width,
                            height: Get.height,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    _navButton(
                      alignment: Alignment.centerLeft,
                      icon: Icons.chevron_left,
                      visible: controller.canGoPrevious,
                      onPressed: controller.previous,
                    ),
                    _navButton(
                      alignment: Alignment.centerRight,
                      icon: Icons.chevron_right,
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
        'No image found',
        style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 14),
      ),
    );
  }

  Widget _navButton({
    required Alignment alignment,
    required IconData icon,
    required bool visible,
    required VoidCallback onPressed,
  }) {
    if (!visible) return const SizedBox.shrink();

    return Align(
      alignment: alignment,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(backgroundColor: AppColor.black120),
        icon: Icon(icon, size: 38),
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
                    color: selected ? Colors.green : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _image(
                  image,
                  width: 116,
                  height: 68,
                  fit: BoxFit.cover,
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
        errorBuilder: (_, __, ___) => _brokenImage(width, height),
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
    return Icon(
      Icons.broken_image,
      color: Colors.white.withAlpha(160),
      size: 48,
    ).wh(width, height);
  }
}
