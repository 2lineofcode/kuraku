import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../core/app_translations.dart';
import '../data/database/db_profile.dart';
import '../modules/widgets/widget_style.dart';


class BadgeProgress {
  final String currentTitle;
  final String nextTitle;
  final int currentValue;
  final int targetValue;
  final int startValue;
  final bool isMaxLevel;

  BadgeProgress({
    required this.currentTitle,
    required this.nextTitle,
    required this.currentValue,
    required this.targetValue,
    required this.isMaxLevel,
    this.startValue = 0,
  });

  int get percent {
    if (isMaxLevel) return 100;
    if (targetValue <= startValue) return 0;
    return (((currentValue - startValue) / (targetValue - startValue)) * 100).clamp(0, 100).toInt();
  }
}

mixin HelperBadge {
  static String getBadgeWatchDurationText(int seconds) => DBProfile.watchDurationBadge(seconds).tr;

  static String getBadgeTotVidText(int count) => DBProfile.collectionBadge((count < 0 ? 0 : count)).tr;

  static BadgeProgress getCollectionProgress(int count) {
    final value = (count < 0 ? 0 : count);
    final current = getBadgeTotVidText(value);
    const thresholds = [0, 1, 101, 201, 301, 401, 501, 1001];
    for (var i = 1; i < thresholds.length; i++) {
      if (value < thresholds[i]) return BadgeProgress(currentTitle: current,
        nextTitle: getBadgeTotVidText(thresholds[i]), currentValue: value, targetValue: thresholds[i],
        startValue: thresholds[i - 1], isMaxLevel: false);
    }
    return BadgeProgress(currentTitle: current, nextTitle: current, currentValue: value, targetValue: value, isMaxLevel: true);
  }

  static BadgeProgress getWatchDurationProgress(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final current = getBadgeWatchDurationText(value);
    const thresholds = [0, 1, 11 * 3600, 51 * 3600, 151 * 3600, 301 * 3600];
    for (var i = 1; i < thresholds.length; i++) {
      if (value < thresholds[i]) return BadgeProgress(currentTitle: current,
        nextTitle: getBadgeWatchDurationText(thresholds[i]), currentValue: value, targetValue: thresholds[i],
        startValue: thresholds[i - 1], isMaxLevel: false);
    }
    return BadgeProgress(currentTitle: current, nextTitle: current, currentValue: value, targetValue: value, isMaxLevel: true);
  }

  static String getBadgeTotVidTooltip(int count) {
    if (count == 0) return '~';
    if (count > 0 && count <= 100) {
      return 'Your JAV collection just @{count}, it\'s so Newbie you probably can\'t even remember any actress yet.'.trNamed({'count': '$count'});
    } else if (count > 100 && count <= 200) {
      return 'Nice! You have @{count} videos. You\'re now a real Jav Lover maybe you already have a few favorite stars.'.trNamed({'count': '$count'});
    } else if (count > 200 && count <= 300) {
      return 'Woah @{count} videos?! You\'re becoming a true Jav Hunter always on the lookout for new releases!'.trNamed({'count': '$count'});
    } else if (count > 300 && count <= 400) {
      return 'Damn @{count} vids... you\'re officially a Nolep take a break sometimes, bro.'.trNamed({'count': '$count'});
    } else if (count > 400 && count <= 500) {
      return 'You crossed @{count} videos. Degenerate tier reached keep your library organized.'.trNamed({'count': '$count'});
    } else if (count > 500 && count <= 1000) {
      return 'You got @{count} videos... you\'re a certified Freak you probably know every actress by heart.'.trNamed({'count': '$count'});
    } else {
      return 'Bro... @{count} videos?? You\'re beyond saving Nolep x_x'.trNamed({'count': '$count'});
    }
  }

  static Widget getBadgeTotVidIcons(int count) {
    if (count == 0) return 0.heightBox;

    if (count > 0 && count <= 100) {
      return HugeIcon(icon: HugeIcons.strokeRoundedSmile, size: AppStyle.iconSize, color: Vx.amber300);
    } else if (count > 100 && count <= 200) {
      return HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: AppStyle.iconSize, color: Vx.red400);
    } else if (count > 200 && count <= 300) {
      return HugeIcon(icon: HugeIcons.strokeRoundedTarget01, size: AppStyle.iconSize, color: Vx.amber300);
    } else if (count > 300 && count <= 400) {
      return HugeIcon(icon: HugeIcons.strokeRoundedMoon02, size: AppStyle.iconSize, color: Vx.amber500);
    } else if (count > 400 && count <= 1000) {
      return HugeIcon(icon: HugeIcons.strokeRoundedFire, size: AppStyle.iconSize, color: Vx.red500);
    } else {
      return HugeIcon(icon: HugeIcons.strokeRoundedAward01, size: AppStyle.iconSize, color: Vx.red500);
    }
  }
}
