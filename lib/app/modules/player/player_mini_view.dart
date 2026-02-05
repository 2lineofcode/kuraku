import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_pref.dart';
import '../../routes/app_pages.dart';
import 'player_controller.dart';
import 'player_controls.dart';

class PlayerMiniView extends StatelessWidget {
  const PlayerMiniView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlayerController>();

    return Obx(() {
      if (controller.isPlayerVisible.isFalse || controller.isMiniMode.isFalse) {
        return const SizedBox.shrink();
      }

      return Positioned(
        right: 24,
        bottom: 24,
        child: _MiniPlayerCard(controller: controller),
      );
    });
  }
}

class _MiniPlayerCard extends StatelessWidget {
  const _MiniPlayerCard({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const SeekForward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const SeekBackward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.greater): const NextVideoIntent(),
      LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.less): const PrevVideoIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyP): const MiniPlayerIntent(),

    };

    final actions = <Type, Action<Intent>>{
      SeekForward5sIntent: CallbackAction<SeekForward5sIntent>(
        onInvoke: (intent) {
          controller.seekRelative(Duration(seconds: AppPref.getPlayerSeekShort()));
          return null;
        },
      ),
      SeekBackward5sIntent: CallbackAction<SeekBackward5sIntent>(
        onInvoke: (intent) {
          controller.seekRelative(Duration(seconds: -AppPref.getPlayerSeekShort()));
          return null;
        },
      ),
      NextVideoIntent: CallbackAction<NextVideoIntent>(
        onInvoke: (intent) {
          controller.nextVideo();
          return null;
        },
      ),
      PrevVideoIntent: CallbackAction<PrevVideoIntent>(
        onInvoke: (intent) {
          controller.prevVideo();
          return null;
        },
      ),
      MiniPlayerIntent: CallbackAction<MiniPlayerIntent>(onInvoke: (intent) async {
        controller.exitMiniMode();
        if (Get.currentRoute != Routes.PLAYER) {
          await Get.toNamed(Routes.PLAYER);
        } else {
          controller.requestFocusOnPlayer();
        }
        return null;
      })
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, offset: Offset(0, 8), blurRadius: 24),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSurface(context),
                  _buildProgress(),
                  _buildInfoRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSurface(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        controller.exitMiniMode();
        if (Get.currentRoute != Routes.PLAYER) {
          await Get.toNamed(Routes.PLAYER);
        } else {
          controller.requestFocusOnPlayer();
        }
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ValueListenableBuilder<int?>(
            valueListenable: controller.videoController.id,
            builder: (context, textureId, _) {
              if (textureId == null) {
                return const Center(child: CircularProgressIndicator.adaptive());
              }
              return Video(
                controller: controller.videoController,
                fit: BoxFit.cover,
                fill: Colors.black,
                controls: (state) => const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Obx(() {
      final duration = controller.duration.value.inMilliseconds;
      final position = controller.position.value.inMilliseconds;
      final value = duration == 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);
      return LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.white12,
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
        minHeight: 4,
      );
    });
  }

  Widget _buildInfoRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Obx(
              () => Text(
                controller.currentVideo.value.videoCode?.isNotEmpty == true ? controller.currentVideo.value.videoCode! : controller.currentVideo.value.title ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Previous',
            icon: Icon(UIconsPro.regularRounded.angle_small_left, color: Colors.white),
            onPressed: () => controller.prevVideo(),
          ),
          Obx(() {
            final isPlaying = controller.isPlaying.value;
            return IconButton(
              iconSize: 20,
              tooltip: isPlaying ? 'Pause' : 'Play',
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () => controller.togglePlayPause(),
            );
          }),
          IconButton(
            iconSize: 18,
            tooltip: 'Next',
            icon: Icon(UIconsPro.regularRounded.angle_small_right, color: Colors.white),
            onPressed: () => controller.nextVideo(),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Close',
            icon: Icon(UIconsPro.regularRounded.cross_small, color: Colors.white),
            onPressed: () async {
              await controller.stopPlayback();
            },
          ),
        ],
      ),
    );
  }
}
