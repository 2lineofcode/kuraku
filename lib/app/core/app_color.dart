import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';

mixin AppColor {
  static Color get appBar => Color(0xff141218);
  static Color get footer => Color.fromARGB(255, 18, 15, 22);

  static Color get selected => Vx.violet500.withAlpha(50);
  static Color get unselected => Vx.violet500.withAlpha(50);
  static Color get border => Vx.neutral700.withAlpha(100);
  static Color get container => Vx.neutral900;
}
