import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'player_controller.dart';
import 'player_controls.dart';

class PlayerView extends GetView<PlayerController> {
  const PlayerView({super.key});
  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: controller.onDropEnter,
      onDropLeave: controller.onDropLeave,
      onDropEnded: controller.onDropEnded,
      onDropOver: (event) {
        if (event.session.allowedOperations.contains(DropOperation.copy)) {
          return DropOperation.copy;
        } else {
          return DropOperation.none;
        }
      },
      onPerformDrop: controller.onDropEvent,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          if (controller.isMiniMode.value || controller.isPlayerVisible.isFalse) {
            Get.back();
            return;
          }

          await controller.stopPlayback();
          Get.back();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              controller.obx(
                (state) => ValueListenableBuilder<int?>(
                  valueListenable: controller.videoController.id,
                  builder: (context, textureId, _) {
                    if (textureId == null) {
                      return const Center(child: CircularProgressIndicator.adaptive());
                    }
                    return Obx(
                      () => Video(
                        controller: controller.videoController,
                        fit: controller.videoFit.value,
                        fill: Colors.black,
                        controls: (videoState) => PlayerControls(controller: controller, videoState: videoState),
                      ),
                    );
                  },
                ),
              ),
              _dropOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropOverlay() {
    return Obx(
      () => IgnorePointer(
        ignoring: controller.isDropHovering.isFalse,
        child: AnimatedOpacity(
          opacity: controller.isDropHovering.value ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            color: Colors.black.withValues(alpha: 0.72),
            alignment: Alignment.center,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_open_rounded, color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Drop video or subtitle here'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Videos: .mp4, .mkv, .avi, .mov\nMultiple videos become a playlist\nSubtitle: .srt, .vtt, .ass, .ssa'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
