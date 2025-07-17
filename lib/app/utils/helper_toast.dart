import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:toastification/toastification.dart';

mixin HelperToast {
  static Future<void> error(
    String? message, {
    String? title = 'Ups',
    Duration duration = const Duration(seconds: 2),
    Alignment? alignment,
  }) async {
    toastification.show(
      context: Get.context,
      type: ToastificationType.error,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
    );
  }

  static Future<void> success(
    String? message, {
    String? title = 'Success',
    Duration duration = const Duration(seconds: 2),
    Alignment? alignment,
  }) async {
    toastification.show(
      context: Get.context,
      type: ToastificationType.success,
      title: '$message'.text.size(12).make(),
      animationDuration: 200.milliseconds,
      autoCloseDuration: duration,
      alignment: alignment,
      style: ToastificationStyle.flatColored,
    );
  }
}
