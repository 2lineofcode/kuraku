import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:toastification/toastification.dart';

import '../modules/home/home_panel/home_panel_log.dart';

mixin HelperToast {
  static Future<void> error(
    String? message, {
    String? title = 'Ups',
    Duration duration = const Duration(seconds: 5),
    Alignment? alignment,
  }) async {
    await HomePanelAppLog.add('ERROR', message.toString());
    toastification.show(
      context: Get.context,
      type: ToastificationType.error,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
      showProgressBar: true,
      pauseOnHover: true,
      closeOnClick: true,
    );
  }

  static Future<void> success(
    String? message, {
    String? title = 'Success',
    Duration duration = const Duration(seconds: 2),
    Alignment? alignment,
  }) async {
    await HomePanelAppLog.add('SUCCESS', message.toString());
    toastification.show(
      context: Get.context,
      type: ToastificationType.success,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
      showProgressBar: true,
      pauseOnHover: true,
      closeOnClick: true,
    );
  }

  static Future<void> info(
    String? message, {
    String? title = 'Info',
    Duration duration = const Duration(seconds: 2),
    Alignment? alignment,
  }) async {
    await HomePanelAppLog.add('INFO', message.toString());
    toastification.show(
      context: Get.context,
      type: ToastificationType.info,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
      showProgressBar: true,
      pauseOnHover: true,
      closeOnClick: true,
    );
  }

  static Future<void> warn(
    String? message, {
    String? title = 'Warning',
    Duration duration = const Duration(seconds: 2),
    Alignment? alignment,
  }) async {
    await HomePanelAppLog.add('WARN', message.toString());
    toastification.show(
      context: Get.context,
      type: ToastificationType.warning,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
      showProgressBar: true,
      pauseOnHover: true,
      closeOnClick: true,
    );
  }
}
