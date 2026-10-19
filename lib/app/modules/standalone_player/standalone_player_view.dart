import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../widgets/widget_controls.dart';
import '../widgets/widget_style.dart';
import 'standalone_player_controller.dart';
import 'standalone_player_controls.dart';

class StandalonePlayerView extends StatelessWidget {
  const StandalonePlayerView({super.key, required this.controller});

  final StandalonePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (controller.isPlayerVisible.value) await controller.stopPlayback();
      },
      child: Scaffold(
        body: Obx(() => !controller.isPlayerVisible.value
          ? _PlayerDropPanel(onOpen: controller.pickVideos)
          : controller.obx(
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
                    controls: (videoState) => StandalonePlayerControls(controller: controller, videoState: videoState),
                  ),
                );
              },
            ),
          )),
      ),
    );
  }
}

class StandalonePlayerDropTarget extends StatelessWidget {
  const StandalonePlayerDropTarget({super.key, required this.controller, required this.child});

  final StandalonePlayerController controller;
  final Widget child;

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
      child: Stack(
        fit: StackFit.expand,
        children: [child, _dropOverlay(context)],
      ),
    );
  }

  Widget _dropOverlay(BuildContext context) {
    return Obx(
      () => IgnorePointer(
        ignoring: controller.isDropHovering.isFalse,
        child: AnimatedOpacity(
          opacity: controller.isDropHovering.value ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
            child: const _PlayerDropPanel(hovering: true),
          ),
        ),
      ),
    );
  }
}

class _PlayerDropPanel extends StatelessWidget {
  const _PlayerDropPanel({this.hovering = false, this.onOpen});

  final bool hovering;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DottedBorder(
          options: RoundedRectDottedBorderOptions(
            radius: const Radius.circular(16), dashPattern: const [7, 5],
            color: hovering ? scheme.primary : scheme.onSurface.withValues(alpha: .22),
            strokeWidth: hovering ? 1.6 : 1.2, padding: EdgeInsets.zero,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: BoxDecoration(
              color: (hovering ? scheme.primary : scheme.onSurface).withValues(alpha: hovering ? .06 : .025),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(hovering ? CupertinoIcons.arrow_down_doc : CupertinoIcons.play_rectangle,
                size: AppStyle.emptyIconSize, color: hovering ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text((hovering ? 'Drop video or subtitle here' : 'Drop videos here').tr, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Multiple videos become a playlist'.tr,
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.6)),
              if (onOpen != null) ...[
                const SizedBox(height: 20),
                AppButton(variant: AppButtonVariant.outlined, onPressed: onOpen,
                  borderColor: scheme.outlineVariant, icon: const Icon(CupertinoIcons.folder_open), child: Text('Open files'.tr)),
              ],
            ]),
          ),
        ),
      ),
    ));
  }
}
