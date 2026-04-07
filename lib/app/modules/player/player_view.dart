import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_controller.dart';
import 'player_controls.dart';

class PlayerView extends GetView<PlayerController> {
  const PlayerView({super.key});
  @override
  Widget build(BuildContext context) {
    return PopScope(
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
        body: controller.obx(
          (state) => ValueListenableBuilder<int?>(
            valueListenable: controller.videoController.id,
            builder: (context, textureId, _) {
              if (textureId == null) {
                return const Center(child: CircularProgressIndicator.adaptive());
              }
              return Obx(
                () => Video(
                  key: controller.videoKey,
                  controller: controller.videoController,
                  fit: controller.videoFit.value,
                  fill: Colors.black,
                  controls: (videoState) => PlayerControls(controller: controller),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
