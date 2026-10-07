import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

mixin AppColor {
  // Global palette access still needs a local dependency to rebuild retained views.
  static void dependOn(BuildContext context) { Theme.of(context); }

  static Color get appBar => Get.isDarkMode ? Color(0xff141218) : Color(0xfff3f1f7);
  static Color get footer => Get.isDarkMode ? Color.fromARGB(255, 18, 15, 22) : Color(0xffeeecf2);

  static Color get selected => Get.isDarkMode ? Color.fromARGB(255, 32, 44, 67) : Color(0xffdce6f5);
  static Color get unselected => Colors.transparent;

  static Color get border => (Get.isDarkMode ? Vx.neutral700 : Vx.neutral400).withAlpha(100);
  static Color get container => Get.isDarkMode ? Vx.neutral900 : Vx.neutral100;

  static Color get body => Get.isDarkMode ? Color(0xff0e0c11) : Color(0xfffaf9fc);
  static Color get panel => Get.isDarkMode ? Color(0xff17151b) : Colors.white;
  static Color get hover => Get.isDarkMode ? Vx.neutral800 : Color(0xffe9e7ef);
  static Color get muted => Get.isDarkMode ? Vx.neutral400 : Vx.neutral600;
  static Color get onAccent => Get.theme.colorScheme.onPrimary;
  static Color get accent => Get.theme.colorScheme.primary;
  static Color get success => Get.isDarkMode ? Vx.green400 : Colors.green.shade900;
  static Color get text => Get.theme.colorScheme.onSurface;

  static Color get black120 => Colors.black.withAlpha(120);
  static Color get black170 => Colors.black.withAlpha(170);
  static Color get black180 => Colors.black.withAlpha(180);
}
