import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

mixin AppColor {
  ///
  static Color get _primaryLight => Vx.blue600;
  static Color get noteColor => Vx.blue600;

  /// layout
  static Color get sideMenuPrimary => Get.isDarkMode ? Vx.neutral800 : Vx.neutral100;
  static Color get sideMenuSecondary => Get.isDarkMode ? Vx.neutral700 : Vx.white;
  static Color get appbarPrimary => Get.isDarkMode ?  Color.fromARGB(255, 20, 18, 24) : _primaryLight;
  static Color get footerPrimary => Get.isDarkMode ? Color.fromARGB(255, 18, 15, 22) : Vx.neutral300;
  static Color get emptyStatePrimary => Get.isDarkMode ? Vx.neutral800 : Vx.neutral200;

  /// menu
  static Color get sideMenuSelected => Get.isDarkMode ? const Color(0xff231B4D) : Vx.blue200;
  static Color get menuSelected => Get.isDarkMode ? Colors.blue : Colors.white;
  static Color get menuUnSelected => Get.isDarkMode ? Colors.white : Vx.blue400;

  /// textfield
  static Color get textFieldPrimary => Get.isDarkMode ? Vx.neutral700 : Vx.neutral200;

  /// card item
  static Color get cardHeaderPrimary => Get.isDarkMode ? Vx.neutral900 : Vx.neutral300;
  static Color get cardItemPrimary => Get.isDarkMode ? Vx.neutral700 : Vx.neutral200;
  static Color get cardItemSecondary => Get.isDarkMode ? Vx.neutral800 : Vx.neutral200;

  /// fab
  static Color get fabPrimary => Get.isDarkMode ? Vx.neutral600 : _primaryLight;

  /// text on background (special case)
  static Color get textOnBackground => Get.isDarkMode ? Vx.white : Vx.neutral100;
  static Color get textReverse => Get.isDarkMode ? Vx.white : Vx.black;
  static Color get textOnWhiteBackground => Get.isDarkMode ? Vx.black : Vx.black;

  /// table
  static Color get tableHeader => Get.isDarkMode ? Vx.neutral800 : Vx.neutral300;

  /// shimmer
  static Color get shimmerPrimary => Get.isDarkMode ? Vx.neutral700 : Vx.neutral300;
  static Color get shimmerSecondary => Get.isDarkMode ? Vx.neutral600 : Vx.neutral200;

  /// ------------------------------------------------------------------------
  /// green
  static Color get green => Get.isDarkMode ? Vx.green300 : Vx.green600;
  static Color get greenLight => Get.isDarkMode ? Vx.green200 : Vx.green600;
  static Color get greenDark => Get.isDarkMode ? Vx.green600 : Vx.green600;

  /// bibit
  static Color get bibit => Get.isDarkMode ? Color(0xff4CA870) : Color(0xff4CA870);
  static Color get bibitLight => Get.isDarkMode ? Color(0xff57BF7F) : Color(0xff4CA870);
  static Color get bibitDark => Get.isDarkMode ? Color(0xff1B2D25) : Color(0xffEDF8F3);

  /// orange
  static Color get orange => Get.isDarkMode ? Vx.orange300 : Vx.orange500;
  static Color get orangeLight => Get.isDarkMode ? Vx.orange200 : Vx.orange500;
  static Color get orangeDark => Get.isDarkMode ? Vx.orange600 : Vx.orange500;

  /// red
  static Color get red => Get.isDarkMode ? Vx.red400 : Vx.red600;
  static Color get redLight => Get.isDarkMode ? Vx.red200 : Vx.red600;
  static Color get redDark => Get.isDarkMode ? Vx.red600 : Vx.red600;

  /// blue
  static Color get blue => Get.isDarkMode ? Vx.blue300 : Vx.blue600;

  /// neutral
  static Color get neutral => Get.isDarkMode ? Vx.neutral700 : Vx.neutral300;
  static Color get neutralLight => Get.isDarkMode ? Vx.neutral300 : Vx.neutral700;
}
