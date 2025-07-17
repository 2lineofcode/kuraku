import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_color.dart';
import 'app_setting.dart';
import 'const.dart';

mixin AppTheme {
  /// * light
  static final light = ThemeData.light(useMaterial3: true).copyWith(
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(color: Colors.white),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: AppColor.noteColor,
      labelColor: AppColor.textReverse,
      labelStyle: TextStyle(fontSize: 13),
      unselectedLabelColor: Vx.neutral400,
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),
    dividerColor: AppColor.neutral,
  );

  /// * dark
  static final dark = ThemeData.dark(useMaterial3: true).copyWith(
    tabBarTheme: TabBarThemeData(
      indicatorColor: AppColor.noteColor,
      labelColor: AppColor.textReverse,
      labelStyle: TextStyle(fontSize: 13),
      unselectedLabelColor: Vx.neutral400,
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),
    dividerColor: AppColor.neutral,
  );

  /// load theme
  static bool _isDarkMode() => pref.read(kIsDarkMode) ?? true;

  static ThemeMode get currentTheme => _isDarkMode() ? ThemeMode.dark : ThemeMode.light;

  static Future<void> switchTheme() async {
    Get.changeThemeMode(_isDarkMode() ? ThemeMode.light : ThemeMode.dark);
    await pref.write(kIsDarkMode, !_isDarkMode());
    await 600.milliseconds.delay();
    await Get.forceAppUpdate();
  }
}
