import 'package:chewie/chewie.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import 'player_controller.dart';

class PlayerView extends GetView<PlayerController> {
  const PlayerView({super.key});
  @override
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, Intent> shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyL): const OpenListIntent(),
      const SingleActivator(LogicalKeyboardKey.keyQ): const BackIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): const OpenScreenshotIntent(),
      const SingleActivator(LogicalKeyboardKey.keyI): const OpenInfoIntent(),
      const SingleActivator(LogicalKeyboardKey.greater, shift: true): const NextVideoIntent(),
      const SingleActivator(LogicalKeyboardKey.less, shift: true): const PrevVideoIntent(),
    };

    final Map<Type, Action<Intent>> actions = <Type, Action<Intent>>{
      OpenListIntent: CallbackAction<OpenListIntent>(onInvoke: (intent) => controller.openList()),
      BackIntent: CallbackAction<BackIntent>(onInvoke: (intent) => Get.back()),
      NextVideoIntent: CallbackAction<NextVideoIntent>(onInvoke: (intent) => controller.nextVideo()),
      PrevVideoIntent: CallbackAction<PrevVideoIntent>(onInvoke: (intent) => controller.prevVideo()),
      OpenScreenshotIntent: CallbackAction<OpenScreenshotIntent>(onInvoke: (intent) => controller.openSS()),
      OpenInfoIntent: CallbackAction<OpenInfoIntent>(onInvoke: (intent) => controller.openInfo()),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: controller.obx(
        (state) => FocusScope(
          autofocus: true,
          child: Shortcuts(
            shortcuts: shortcuts,
            child: Actions(
              actions: actions,
              child: Focus(
                focusNode: controller.fnMain,
                autofocus: true,
                child: ZStack(
                  [
                    controller.cachePlayer.isInitialized 
                      ? Chewie(controller: controller.chewie)
                      : const CircularProgressIndicator.adaptive(),

                    if (controller.isFullScreen.isFalse) ...[
                      Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                        child: Icon(UIconsPro.regularRounded.cross_small, size: 14).p8(),
                      ).onInkTap(() => Get.back()).positioned(right: 8, top: 8),
                      Container(
                        decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                        child: Icon(UIconsPro.regularRounded.list, size: 14).p8(),
                      ).onInkTap(() => controller.openList()).positioned(right: 44, top: 8),
                    ],

                    Obx(
                      () => FadeTransition(
                        opacity: controller.infoAnimationController,
                        child: controller.infoOverlayText.value.isEmpty
                            ? const SizedBox.shrink()
                            : controller.infoOverlayText.value.text.bold.white.make().pSymmetric(h: 8, v: 4).box.color(AppColor.selected).make().cornerRadius(90),
                      ).positioned(right: 12, top: 44),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenListIntent extends Intent { const OpenListIntent(); }
class BackIntent extends Intent { const BackIntent(); }
class NextVideoIntent extends Intent { const NextVideoIntent(); }
class PrevVideoIntent extends Intent { const PrevVideoIntent(); }
class OpenScreenshotIntent extends Intent { const OpenScreenshotIntent(); }
class OpenInfoIntent extends Intent { const OpenInfoIntent(); }
