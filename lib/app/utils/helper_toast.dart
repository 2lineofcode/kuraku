import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:toastification/toastification.dart';

import '../modules/home/home_panel/home_panel_log.dart';
import '../modules/widgets/widget_controls.dart';
import '../modules/widgets/widget_style.dart';

mixin HelperToast {
  static final _closeButton = ToastCloseButton(buttonBuilder: (context, onClose) => AppIconButton(
    tooltip: 'Close'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize), onPressed: onClose,
  ));

  static Future<void> error(
    String? message, {
    String? title = 'Ups',
    Duration duration = const Duration(seconds: 5),
    Alignment? alignment,
    bool? addToAppLog = true,
  }) async {
    if (addToAppLog == true) {
      await HomePanelAppLog.add('ERROR', message.toString());
    }
    toastification.show(
      context: Get.context,
      type: ToastificationType.error,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: AppStyle.largeIconSize),
      closeButton: _closeButton,
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
    bool? addToAppLog = true,
  }) async {
    if (addToAppLog == true) {
      await HomePanelAppLog.add('SUCCESS', message.toString());
    }
    toastification.show(
      context: Get.context,
      type: ToastificationType.success,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: AppStyle.largeIconSize),
      closeButton: _closeButton,
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
    bool? addToAppLog = true,
  }) async {
    if (addToAppLog == true) {
      await HomePanelAppLog.add('INFO', message.toString());
    }
    toastification.show(
      context: Get.context,
      type: ToastificationType.info,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.largeIconSize),
      closeButton: _closeButton,
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
    bool? addToAppLog = true,
  }) async {
    if (addToAppLog == true) {
      await HomePanelAppLog.add('WARN', message.toString());
    }
    toastification.show(
      context: Get.context,
      type: ToastificationType.warning,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedAlert02, size: AppStyle.largeIconSize),
      closeButton: _closeButton,
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
