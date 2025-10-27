import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:uicons_pro/uicons_pro.dart';

mixin HelperBadge {
  static String getBadgeTotVidText(int count) {
    if (count == 0) return 'Noobless';
    if (count > 0 && count <= 100) {
      return 'Newbie Explorer';
    } else if (count > 100 && count <= 200) {
      return 'Jav Lover';
    } else if (count > 200 && count <= 300) {
      return 'Jav Hunter';
    } else if (count > 300 && count <= 400) {
      return 'True Nolep';
    } else if (count > 400 && count <= 500) {
      return 'Degenerate';
    } else if (count > 500 && count <= 1000) {
      return 'Certified Freak';
    } else {
      return 'Nolep x_x (beyond redemption)';
    }
  }

  static String getBadgeTotVidTooltip(int count) {
    if (count == 0) return '~';
    if (count > 0 && count <= 100) {
      return 'Your JAV collection just $count, it\'s so Newbie 😅 you probably can\'t even remember any actress yet.';
    } else if (count > 100 && count <= 200) {
      return 'Nice! You have $count videos. You\'re now a real Jav Lover ❤️ maybe you already have a few favorite stars.';
    } else if (count > 200 && count <= 300) {
      return 'Woah $count videos?! You\'re becoming a true Jav Hunter 🔥 always on the lookout for new releases!';
    } else if (count > 300 && count <= 400) {
      return 'Damn $count vids... you\'re officially a Nolep 😬 take a break sometimes, bro.';
    } else if (count > 500 && count <= 1000) {
      return 'You got $count videos... you\'re a certified Freak 😈 you probably know every actress by heart.';
    } else {
      return 'Bro... $count videos?? You\'re beyond saving 😭 Nolep x_x';
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
