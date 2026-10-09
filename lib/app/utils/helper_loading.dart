import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../core/app_color.dart';
import '../core/app_translations.dart';
import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_surfaces.dart';

mixin HelperLoading {
  static final _stopwatch = Stopwatch();
  static Timer? _timer;
  static Timer? _cancelTimer;
  static OverDialog? _overlay;
  static bool _isMounted = false;

  static void show({
    bool isDismissible = true,
    String? message,
    void Function()? cancelCallback,
  }) {
    dismiss();
    _stopwatch.reset();
    _stopwatch.start();
    final showCancel = false.obs;
    final messageText = (message == null) ? ''.obs : message.obs;

    if (message == null) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (_overlay != null) {
          final time = _stopwatch.elapsed;
          final seconds = time.inSeconds % 60;
          final minutes = time.inMinutes % 60;
          final hours = time.inHours;

          final formattedTime = hours > 0
              ? '@{hours}h @{minutes}m @{seconds}s'.trNamed({'hours': '$hours', 'minutes': '$minutes', 'seconds': '$seconds'})
              : minutes > 0
                  ? '@{minutes}m @{seconds}s'.trNamed({'minutes': '$minutes', 'seconds': '$seconds'})
                  : '@{seconds} seconds'.trNamed({'seconds': '$seconds'});

          messageText.value = '$formattedTime';
        } else {
          timer.cancel();
          _stopwatch.stop();
        }
      });
    }

    _cancelTimer = Timer(15.seconds, () => showCancel.value = true);

    late final OverDialog overlay;
    overlay = OverDialog(
      width: 150,
      decoration: const BoxDecoration(),
      backgroundSettings: BackgroundSettings(blur: 0, color: Colors.black54, dismissOnClick: isDismissible),
      actions: OverlayActions(
        onOpen: () async {
          if (_overlay == overlay) {
            _isMounted = true;
          } else {
            // Overlayment initializes its animation only after the first build.
            WidgetsBinding.instance.addPostFrameCallback((_) => Overlayment.dismiss(overlay));
          }
        },
        onClose: (result) async {
          if (_overlay == overlay) {
            _timer?.cancel();
            _cancelTimer?.cancel();
            _stopwatch.stop();
            _overlay = null;
            _isMounted = false;
          }
          return result;
        },
      ),
      child: AppPanel(
        color: AppColor.panel,
        bordered: true,
        padding: EdgeInsets.zero,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 100),
          child: VStack(
            [
              LoadingAnimationWidget.discreteCircle(color: Theme.of(Get.context!).primaryColor, size: 32).centered(),

              Obx(() => Text(messageText.value, textAlign: TextAlign.center, style: TextStyle(fontSize: 10)).centered().pOnly(top: 16)),

              Obx(
                () => showCancel.value == true
                    ? AppButton(
                        label: 'Cancel'.tr,
                        height: 40,
                        labelSize: 11,
                        onPressed: cancelCallback ?? dismiss,
                      ).pOnly(top: 8).centered()
                    : 0.heightBox,
              ),
            ],
          ).p12(),
        ),
      ),
    );
    _overlay = overlay;
    WidgetsBinding.instance.scheduleFrame();
    unawaited(Overlayment.show(overlay, context: Get.context));
  }

  static void dismiss() {
    _timer?.cancel();
    _cancelTimer?.cancel();
    _stopwatch.stop();
    final overlay = _overlay;
    _overlay = null;
    if (overlay != null && _isMounted) unawaited(Overlayment.dismiss(overlay));
    _isMounted = false;
  }
}
