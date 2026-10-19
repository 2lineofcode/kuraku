import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/app_translations.dart';
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
          ? _PlayerHome(controller: controller)
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

class _PlayerHome extends StatefulWidget {
  const _PlayerHome({required this.controller});

  final StandalonePlayerController controller;

  @override
  State<_PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<_PlayerHome> {
  final _packageInfo = PackageInfo.fromPlatform();

  String _formatPosition(Duration value) => value.inHours > 0 ? value.toString().split('.').first
    : '${value.inMinutes.toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    return Align(alignment: Alignment.topCenter, child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Image.asset('assets/app_icon.png', width: 64, height: 64, excludeFromSemantics: true),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('KuraKu', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return Text(info == null ? '' : 'v${info.version}${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11));
                },
              ),
            ])),
            const SizedBox(width: 12),
            AppButton(variant: AppButtonVariant.tonal, onPressed: controller.pickVideos,
              child: Text('Open files'.tr)),
          ]),
          const SizedBox(height: 28),
          Obx(() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (controller.recentError.value)
              Row(children: [
                Expanded(child: Text('Recent files unavailable'.tr, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
                AppButton(variant: AppButtonVariant.text, onPressed: controller.refreshRecent, child: Text('Retry'.tr)),
              ]),
            if (controller.recentFiles.isEmpty)
              const _PlayerDropPanel()
            else ...[
              Row(children: [
                Expanded(child: Text('Recent files'.tr, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11))),
                AppButton(variant: AppButtonVariant.text, onPressed: () => controller.removeRecent(), child: Text('Clear recent'.tr)),
              ]),
              const SizedBox(height: 6),
              for (final item in controller.recentFiles) ...[
                Material(
                  color: scheme.onSurface.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(8),
                  child: Tooltip(message: item.path, child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => controller.openRecent(item),
                    child: Padding(padding: const EdgeInsets.only(left: 12, right: 4, top: 5, bottom: 5), child: Row(children: [
                      Icon(CupertinoIcons.clock, size: 17, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.position > Duration.zero
                        ? 'Resume @{file}'.trNamed({'file': p.basename(item.path)}) : p.basename(item.path),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 13))),
                      const SizedBox(width: 12),
                      Text(_formatPosition(item.position), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                      const SizedBox(width: 6),
                      AppIconButton(icon: const Icon(CupertinoIcons.xmark, size: 12), tooltip: 'Remove from recent'.tr,
                        onPressed: () => controller.removeRecent(item.path)),
                    ])),
                  )),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 18),
              Text('Drop videos here'.tr, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ])),
        ]),
      ),
    ));
  }
}

class _PlayerDropPanel extends StatelessWidget {
  const _PlayerDropPanel({this.hovering = false});

  final bool hovering;

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
            ]),
          ),
        ),
      ),
    ));
  }
}
