import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';
import '../core/app_translations.dart';


class BadgeProgress {
  final String currentTitle;
  final String nextTitle;
  final int currentValue;
  final int targetValue;
  final bool isMaxLevel;

  BadgeProgress({
    required this.currentTitle,
    required this.nextTitle,
    required this.currentValue,
    required this.targetValue,
    required this.isMaxLevel,
  });

  int get percent {
    if (isMaxLevel) return 100;
    if (targetValue <= 0) return 0;
    return ((currentValue / targetValue) * 100).clamp(0, 100).toInt();
  }
}

mixin HelperBadge {
  static String getBadgeWatchDurationText(int seconds) {
    if (seconds <= 0) return 'Fresh Eyes'.tr;

    final hours = seconds ~/ 3600;
    if (hours <= 10) {
      return 'Warm Up'.tr;
    } else if (hours <= 50) {
      return 'Night Owl'.tr;
    } else if (hours <= 150) {
      return 'Screen Warrior'.tr;
    } else if (hours <= 300) {
      return 'Marathoner'.tr;
    } else {
      return 'Time Bender'.tr;
    }
  }

  static String getBadgeTotVidText(int count) {
    if (count == 0) return 'Noobless'.tr;
    if (count > 0 && count <= 100) {
      return 'Newbie Explorer'.tr;
    } else if (count > 100 && count <= 200) {
      return 'Jav Lover'.tr;
    } else if (count > 200 && count <= 300) {
      return 'Jav Hunter'.tr;
    } else if (count > 300 && count <= 400) {
      return 'True Nolep'.tr;
    } else if (count > 400 && count <= 500) {
      return 'Degenerate'.tr;
    } else if (count > 500 && count <= 1000) {
      return 'Certified Freak'.tr;
    } else {
      return 'Nolep x_x (beyond redemption)'.tr;
    }
  }

  static BadgeProgress getCollectionProgress(int count) {
    final current = getBadgeTotVidText(count);
    if (count <= 100) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Jav Lover'.tr, currentValue: count, targetValue: 101, isMaxLevel: false);
    } else if (count <= 200) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Jav Hunter'.tr, currentValue: count, targetValue: 201, isMaxLevel: false);
    } else if (count <= 300) {
      return BadgeProgress(currentTitle: current, nextTitle: 'True Nolep'.tr, currentValue: count, targetValue: 301, isMaxLevel: false);
    } else if (count <= 400) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Degenerate'.tr, currentValue: count, targetValue: 401, isMaxLevel: false);
    } else if (count <= 500) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Certified Freak'.tr, currentValue: count, targetValue: 501, isMaxLevel: false);
    } else if (count <= 1000) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Nolep x_x (beyond redemption)'.tr, currentValue: count, targetValue: 1001, isMaxLevel: false);
    }

    return BadgeProgress(currentTitle: current, nextTitle: current, currentValue: count, targetValue: count, isMaxLevel: true);
  }

  static BadgeProgress getWatchDurationProgress(int seconds) {
    final current = getBadgeWatchDurationText(seconds);
    final hours = seconds ~/ 3600;
    if (hours <= 10) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Night Owl'.tr, currentValue: hours, targetValue: 11, isMaxLevel: false);
    } else if (hours <= 50) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Screen Warrior'.tr, currentValue: hours, targetValue: 51, isMaxLevel: false);
    } else if (hours <= 150) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Marathoner'.tr, currentValue: hours, targetValue: 151, isMaxLevel: false);
    } else if (hours <= 300) {
      return BadgeProgress(currentTitle: current, nextTitle: 'Time Bender'.tr, currentValue: hours, targetValue: 301, isMaxLevel: false);
    }

    return BadgeProgress(currentTitle: current, nextTitle: current, currentValue: hours, targetValue: hours, isMaxLevel: true);
  }

  static String getBadgeTotVidTooltip(int count) {
    if (count == 0) return '~';
    if (count > 0 && count <= 100) {
      return 'Your JAV collection just @{count}, it\'s so Newbie 😅 you probably can\'t even remember any actress yet.'.trNamed({'count': '$count'});
    } else if (count > 100 && count <= 200) {
      return 'Nice! You have @{count} videos. You\'re now a real Jav Lover ❤️ maybe you already have a few favorite stars.'.trNamed({'count': '$count'});
    } else if (count > 200 && count <= 300) {
      return 'Woah @{count} videos?! You\'re becoming a true Jav Hunter 🔥 always on the lookout for new releases!'.trNamed({'count': '$count'});
    } else if (count > 300 && count <= 400) {
      return 'Damn @{count} vids... you\'re officially a Nolep 😬 take a break sometimes, bro.'.trNamed({'count': '$count'});
    } else if (count > 400 && count <= 500) {
      return 'You crossed @{count} videos. Degenerate tier reached 😵 keep your library organized.'.trNamed({'count': '$count'});
    } else if (count > 500 && count <= 1000) {
      return 'You got @{count} videos... you\'re a certified Freak 😈 you probably know every actress by heart.'.trNamed({'count': '$count'});
    } else {
      return 'Bro... @{count} videos?? You\'re beyond saving 😭 Nolep x_x'.trNamed({'count': '$count'});
    }
  }

  static Widget getBadgeTotVidIcons(int count) {
    if (count == 0) return 0.heightBox;

    if (count > 0 && count <= 100) {
      return Icon(UIconsPro.solidRounded.face_smile_horns, size: 12, color: Vx.amber300);
    } else if (count > 100 && count <= 200) {
      return Icon(UIconsPro.solidRounded.leaf_heart, size: 12, color: Vx.red400);
    } else if (count > 200 && count <= 300) {
      return Icon(UIconsPro.solidRounded.tank_water, size: 12, color: Vx.amber300);
    } else if (count > 300 && count <= 400) {
      return Icon(UIconsPro.solidRounded.sushi_roll, size: 12, color: Vx.amber500);
    } else if (count > 400 && count <= 1000) {
      return Icon(UIconsPro.solidRounded.face_angry_horns, size: 12, color: Vx.red500);
    } else {
      return Icon(UIconsPro.solidRounded.face_sunglasses, size: 12, color: Vx.red500);
    }
  }
}
