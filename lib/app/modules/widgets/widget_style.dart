import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';

class AppStyle {
  static const double fontSize = 12;
  static const double radius = 6;
  static const double controlHeight = 30;
  static const double inputHeight = 32;
  static const double iconSize = 16;
  static const double smallIconSize = 12;
  static const double largeIconSize = 24;
  static const double playbackIconSize = 32;
  static const double emptyIconSize = 48;
  static const double iconTarget = 32;
  static const double panelPadding = 12;

  static BoxDecoration inputDecoration(BuildContext context) {
    AppColor.dependOn(context);
    return BoxDecoration(
      color: AppColor.body,
      border: Border.all(color: AppColor.border),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static ThemeData theme(Brightness brightness) {
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    final storedAccent = AppPref.getAppAccent();
    final accent = storedAccent == null ? AppColor.defaultAccent(brightness) : Color(storedAccent);
    return theme.copyWith(
      cupertinoOverrideTheme: const CupertinoThemeData(primaryColor: CupertinoColors.activeBlue, primaryContrastingColor: CupertinoColors.white),
      colorScheme: theme.colorScheme.copyWith(primary: accent,
        onPrimary: Color.alphaBlend(accent, theme.colorScheme.surface).computeLuminance() > .179 ? Colors.black : Colors.white),
      textTheme: theme.textTheme.copyWith(
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: fontSize),
        bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: 13),
        labelLarge: theme.textTheme.labelLarge?.copyWith(fontSize: fontSize),
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
        titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
      ),
      iconTheme: theme.iconTheme.copyWith(size: iconSize),
      menuTheme: MenuThemeData(style: MenuStyle(
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radius)))),
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
      )),
      chipTheme: theme.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        labelStyle: const TextStyle(fontSize: 11),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + 2)),
      ),
    );
  }
}
