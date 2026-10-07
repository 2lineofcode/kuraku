import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/app_translations.dart';
import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_surfaces.dart';

mixin HelperLoading {
  static final _stopwatch = Stopwatch();
  static Timer? _timer;

  static void show({
    bool isDismissible = true,
    String? message,
    void Function()? cancelCallback,
  }) {
    _stopwatch.reset();
    _stopwatch.start();
    final showCancel = false.obs;
    final messageText = (message == null) ? ''.obs : message.obs;

    if (message == null) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (Get.isDialogOpen == true) {
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

    Future.delayed(15.seconds, () => showCancel.value = true);

    Get.dialog(
      Center(
        child: SizedBox(
          width: 200,
          child: AppDialog(
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
                            onPressed: cancelCallback ?? Get.back,
                          ).pOnly(top: 8).centered()
                        : 0.heightBox,
                  ),
                ],
              ).p12(),
            ),
          ),
        ),
      ),
      barrierDismissible: isDismissible,
    );
  }

  static void dismiss() {
    _timer?.cancel();
    _stopwatch.stop();
    if (Get.isDialogOpen == true) Get.back();
  }
}
