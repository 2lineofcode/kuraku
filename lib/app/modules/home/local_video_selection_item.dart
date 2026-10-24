import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import '../../core/app_logging.dart';
import '../../core/app_translations.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper_toast.dart';
import '../widgets/widgets.dart';
import 'local_video_selection.dart';
import 'page_search/page_search_file_drag.dart';

class LocalVideoSelectionItem extends StatelessWidget {
  const LocalVideoSelectionItem({super.key, required this.controller, required this.video, required this.onSingleTap, required this.onDoubleTap, required this.child, this.onRangeTap});

  final LocalVideoSelection controller;
  final Videos video;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final Widget child;
  final VoidCallback? onRangeTap;

  @override
  Widget build(BuildContext context) {
    return SearchFileDrag(controller: controller, video: video, child: scm.ContextMenuWidget(
      contextMenuIsAllowed: (_) => controller.selectedVideos.isNotEmpty,
      menuProvider: (_) {
        if (controller.isClosed || controller.selectedVideos.isEmpty) return null;
        if (!controller.isSelected(video)) controller.selectedVideos.assignAll([video]);
        final selected = controller.selectedInOrder;
        final revision = controller.selectionRevision;
        scm.MenuAction action(String title, String value) => scm.MenuAction(title: title, callback: () async {
          if (controller.isClosed || revision != controller.selectionRevision) return;
          try {
            await controller.performSelectionAction(value, selected);
          } catch (e) {
            AppLog.logE('Video selection action failed ($value): $e');
            await HelperToast.error(e.toString());
          }
        });
        return scm.Menu(children: [
          action('Play as Playlist'.tr, 'play'),
          action('Play in Grid Player'.tr, 'playMulti'),
          scm.MenuSeparator(),
          action('Add to cart'.tr, 'cart'),
          action('Add to Playlist'.tr, 'playlist'),
          action('Add to favorite'.tr, 'favorite'),
        ]);
      },
      child: DoubleTap(
        onShiftTap: onRangeTap,
        onCommandTap: () => controller.toggleSelection(video),
        onSingleTap: () {
          controller.selectedVideos.clear();
          onSingleTap();
        },
        onDoubleTap: () {
          controller.selectedVideos.clear();
          onDoubleTap();
        },
        child: Obx(() => Semantics(
          selected: controller.isSelected(video),
          child: Stack(children: [
            child,
            if (controller.isSelected(video))
              Positioned.fill(child: IgnorePointer(child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(55),
                  border: Border.all(color: Colors.lightBlueAccent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ))),
          ]),
        )),
      ),
    ));
  }
}

class LocalVideoSelectionClear extends StatelessWidget {
  const LocalVideoSelectionClear({super.key, required this.controller});
  final LocalVideoSelection controller;

  @override
  Widget build(BuildContext context) => Obx(() => controller.selectedVideos.isEmpty ? const SizedBox.shrink() : AppButton(
    onPressed: controller.selectedVideos.clear,
    child: Text('@{length} selected · Clear'.trNamed({'length': '${controller.selectedVideos.length}'}), style: const TextStyle(fontSize: 12)),
  ));
}
