import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppAccentTheme extends ThemeExtension<AppAccentTheme> {
  const AppAccentTheme(this.color);

  final Color color;

  @override
  AppAccentTheme copyWith({Color? color}) => AppAccentTheme(color ?? this.color);

  @override
  AppAccentTheme lerp(covariant AppAccentTheme? other, double t) =>
      other == null ? this : AppAccentTheme(Color.lerp(color, other.color, t)!);
}

mixin AppColor {
  // Global palette access still needs a local dependency to rebuild retained views.
  static void dependOn(BuildContext context) { Theme.of(context); }

  static Color appBarFor(Brightness brightness) => brightness == Brightness.dark ? Color(0xff141218) : Color(0xfff3f1f7);
  static Color get appBar => appBarFor(Get.theme.brightness);
  static Color footerFor(Brightness brightness) => brightness == Brightness.dark ? Color.fromARGB(255, 18, 15, 22) : Color(0xffeeecf2);
  static Color get footer => footerFor(Get.theme.brightness);

  static Color defaultAccent(Brightness brightness) => brightness == Brightness.dark ? Color.fromARGB(255, 32, 44, 67) : Color(0xffdce6f5);
  static Color get selected => Get.theme.colorScheme.primaryContainer;
  static Color get unselected => Colors.transparent;

  static Color get border => (Get.isDarkMode ? Vx.neutral700 : Vx.neutral400).withAlpha(100);
  static Color containerFor(Brightness brightness) => brightness == Brightness.dark ? Vx.neutral900 : Vx.neutral100;
  static Color get container => containerFor(Get.theme.brightness);

  static Color bodyFor(Brightness brightness) => brightness == Brightness.dark ? Color(0xff0e0c11) : Color(0xfffaf9fc);
  static Color get body => bodyFor(Get.theme.brightness);
  static Color panelFor(Brightness brightness) => brightness == Brightness.dark ? Color(0xff17151b) : Colors.white;
  static Color get panel => panelFor(Get.theme.brightness);
  static Color hoverFor(Brightness brightness) => brightness == Brightness.dark ? Vx.neutral800 : Color(0xffe9e7ef);
  static Color get hover => hoverFor(Get.theme.brightness);
  static Color get muted => Get.isDarkMode ? Vx.neutral400 : Vx.neutral600;
  static Color get onSelected => Get.theme.colorScheme.onPrimaryContainer;
  static Color get accent => Get.theme.extension<AppAccentTheme>()?.color ?? Get.theme.colorScheme.primary;
  static Color get accentForeground => Get.theme.colorScheme.primary;

  static double contrast(Color foreground, Color background) {
    final a = Color.alphaBlend(foreground, background).computeLuminance();
    final b = background.computeLuminance();
    return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
  }

  static Color readableAccent(Color accent, List<Color> surfaces, Color fallback) {
    final color = Color.alphaBlend(accent, surfaces.first);
    for (var step = 0; step <= 20; step++) {
      final candidate = Color.lerp(color, fallback, step / 20)!;
      if (surfaces.every((surface) => contrast(candidate, surface) >= 4.5)) return candidate;
    }
    return fallback;
  }
  static Color get success => Get.isDarkMode ? Vx.green400 : Colors.green.shade900;
  static Color get text => Get.theme.colorScheme.onSurface;

  static Color get black120 => Colors.black.withAlpha(120);
  static Color get black170 => Colors.black.withAlpha(170);
  static Color get black180 => Colors.black.withAlpha(180);
}
