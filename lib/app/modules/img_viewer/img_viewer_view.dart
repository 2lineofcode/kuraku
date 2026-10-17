import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import '../../core/app_shortcut.dart';
import '../../data/models/library_entity.dart';
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

    return CallbackShortcuts(
      bindings: {
        const AppShortcut(LogicalKeyboardKey.keyB, includeRepeats: false): () => controller.toggleAlbumPanel(),
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: AppColor.appBar,
          toolbarHeight: 44,
          leadingWidth: isMacOS ? (88 + macBackInset) : 88,
          titleSpacing: isMacOS ? 4 : NavigationToolbar.kMiddleSpacing,
          actionsPadding: EdgeInsets.only(right: 4, left: isMacOS ? 8 : 0),
          toolbarTextStyle: TextStyle(fontSize: 14, color: AppColor.text),
          titleTextStyle: TextStyle(fontSize: 14, color: AppColor.text),
          iconTheme: const IconThemeData(size: AppStyle.iconSize),
          title: Padding(
            padding: EdgeInsets.only(left: macTitleInset),
            child: Obx(() {
              final counter = controller.images.isEmpty ? '' : '  ${controller.selectedIndex.value + 1}/${controller.images.length}';
              return Text('${controller.currentTitle}$counter', maxLines: 1, overflow: TextOverflow.ellipsis);
            }),
          ),
          leading: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: macBackInset),
              child: Row(children: [
                AppIconButton(tooltip: 'Back'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft02, size: AppStyle.iconSize), onPressed: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 4),
                AppIconButton(tooltip: AppShortcut.label('${'Image Albums'.tr} (⌘B)'),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedSidebarLeft, size: AppStyle.iconSize),
                  onPressed: controller.toggleAlbumPanel),
              ]),
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

            if (event.logicalKey == LogicalKeyboardKey.keyQ || event.logicalKey == LogicalKeyboardKey.escape || event.logicalKey == LogicalKeyboardKey.arrowDown) {
              Get.back();
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: Obx(() => Row(children: [
            if (controller.albumPanelVisible.value) _albumPanel(),
            Expanded(child: Obx(() {
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
            })),
          ])),
        ),
      ),
    );
  }

  Widget _albumPanel() {
    Widget row(String label, String root, {Library? album}) {
      final available = album == null ? !controller.albumsLoading.value && controller.albumError.value.isEmpty
        : Directory(album.rootFolder ?? '').existsSync();
      return Semantics(selected: controller.selectedAlbumRoot.value == root, child: Material(
        color: controller.selectedAlbumRoot.value == root ? AppColor.selected : Colors.transparent,
        child: InkWell(
          onTap: available ? () => controller.selectAlbum(album) : null,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: available ? AppColor.text : AppColor.muted)),
              if (album != null && !available) Text('Unavailable'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
            ])),
            if (album != null) Text('${album.images?.length ?? 0}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
          ])),
        ),
      ));
    }
    return Container(
      width: 220,
      decoration: BoxDecoration(color: AppColor.panel, border: Border(right: BorderSide(color: AppColor.border, width: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('Image Albums'.tr,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        row('All'.tr, 'all'),
        Divider(height: 1, color: AppColor.border),
        if (controller.albumsLoading.value) const LinearProgressIndicator(minHeight: 2),
        if (controller.albumError.value.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(controller.albumError.value.tr,
            style: TextStyle(fontSize: 11, color: AppColor.muted))),
        Expanded(child: ListView.builder(
          itemCount: controller.albums.length,
          itemBuilder: (_, index) {
            final album = controller.albums[index];
            return row(album.alias?.trim().isNotEmpty == true ? album.alias! : (album.rootFolder ?? '').split(Platform.pathSeparator).last,
              album.rootFolder ?? '', album: album);
          },
        )),
      ]),
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
                  thumbnailPixelRatio: MediaQuery.devicePixelRatioOf(context),
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
    double? thumbnailPixelRatio,
  }) {
    final file = File(image);
    if (file.existsSync()) {
      return Image(
        image: thumbnailPixelRatio == null ? FileImage(file) : ResizeImage(FileImage(file),
          width: (width * thumbnailPixelRatio).ceil(), height: (height * thumbnailPixelRatio).ceil(),
          policy: ResizeImagePolicy.fit),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _brokenImage(width, height),
      );
    }

    if (file.isAbsolute) return _brokenImage(width, height);

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
