import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/utils/helper_badge.dart';

void main() {
  const hour = 3600;

  test('Watch duration badges switch exactly on their hour boundaries', () {
    expect(HelperBadge.getBadgeWatchDurationText(0), 'Fresh Eyes');
    expect(HelperBadge.getBadgeWatchDurationText(-120), 'Fresh Eyes');
    expect(HelperBadge.getBadgeWatchDurationText(1), 'Warm Up');
    expect(HelperBadge.getBadgeWatchDurationText(10 * hour + 3599), 'Warm Up');
    expect(HelperBadge.getBadgeWatchDurationText(11 * hour), 'Night Owl');
    expect(HelperBadge.getBadgeWatchDurationText(50 * hour), 'Night Owl');
    expect(HelperBadge.getBadgeWatchDurationText(51 * hour), 'Screen Warrior');
    expect(HelperBadge.getBadgeWatchDurationText(150 * hour), 'Screen Warrior');
    expect(HelperBadge.getBadgeWatchDurationText(151 * hour), 'Marathoner');
    expect(HelperBadge.getBadgeWatchDurationText(300 * hour), 'Marathoner');
    expect(HelperBadge.getBadgeWatchDurationText(301 * hour), 'Time Bender');
  });

  test('Collection badges switch exactly on their video count boundaries', () {
    const expected = {
      0: 'Noobless',
      1: 'Newbie Explorer',
      100: 'Newbie Explorer',
      101: 'Jav Lover',
      200: 'Jav Lover',
      201: 'Jav Hunter',
      300: 'Jav Hunter',
      301: 'True Nolep',
      400: 'True Nolep',
      401: 'Degenerate',
      500: 'Degenerate',
      501: 'Certified Freak',
      1000: 'Certified Freak',
      1001: 'Nolep x_x (beyond redemption)',
    };
    expected.forEach((count, title) => expect(HelperBadge.getBadgeTotVidText(count), title, reason: 'count $count'));
  });

  test('Collection progress reports the next tier, its target and a clamped percentage', () {
    final fresh = HelperBadge.getCollectionProgress(0);
    expect([fresh.currentTitle, fresh.nextTitle, fresh.currentValue, fresh.targetValue, fresh.isMaxLevel, fresh.percent],
        ['Noobless', 'Newbie Explorer', 0, 1, false, 0]);

    final halfway = HelperBadge.getCollectionProgress(50);
    expect([halfway.currentTitle, halfway.nextTitle, halfway.targetValue, halfway.percent], ['Newbie Explorer', 'Jav Lover', 101, 49]);

    final hunter = HelperBadge.getCollectionProgress(250);
    expect([hunter.currentTitle, hunter.nextTitle, hunter.targetValue, hunter.isMaxLevel], ['Jav Hunter', 'True Nolep', 301, false]);
    expect(hunter.percent, 49);
    expect(HelperBadge.getCollectionProgress(201).percent, 0);
    expect(HelperBadge.getCollectionProgress(-1).currentValue, 0);

    for (final entry in {101: 'Jav Hunter', 201: 'True Nolep', 301: 'Degenerate', 401: 'Certified Freak', 501: 'Nolep x_x (beyond redemption)'}.entries) {
      expect(HelperBadge.getCollectionProgress(entry.key).nextTitle, entry.value, reason: 'count ${entry.key}');
    }

    final maxed = HelperBadge.getCollectionProgress(1001);
    expect(maxed.isMaxLevel, isTrue);
    expect(maxed.nextTitle, maxed.currentTitle);
    expect(maxed.currentValue, 1001);
    expect(maxed.targetValue, 1001);
    expect(maxed.percent, 100);
  });

  test('Watch duration progress keeps second precision and measures the current tier', () {
    final fresh = HelperBadge.getWatchDurationProgress(0);
    expect([fresh.currentTitle, fresh.nextTitle, fresh.currentValue, fresh.targetValue, fresh.percent], ['Fresh Eyes', 'Warm Up', 0, 1, 0]);

    final partial = HelperBadge.getWatchDurationProgress(5 * hour + 1800);
    expect([partial.currentTitle, partial.currentValue, partial.targetValue, partial.percent], ['Warm Up', 5 * hour + 1800, 11 * hour, 49]);

    final owl = HelperBadge.getWatchDurationProgress(20 * hour);
    expect([owl.currentTitle, owl.nextTitle, owl.currentValue, owl.targetValue, owl.percent], ['Night Owl', 'Screen Warrior', 20 * hour, 51 * hour, 22]);

    for (final entry in {51 * hour: 'Marathoner', 151 * hour: 'Time Bender'}.entries) {
      expect(HelperBadge.getWatchDurationProgress(entry.key).nextTitle, entry.value, reason: 'seconds ${entry.key}');
    }

    final maxed = HelperBadge.getWatchDurationProgress(400 * hour);
    expect(maxed.isMaxLevel, isTrue);
    expect(HelperBadge.getWatchDurationProgress(11 * hour).percent, 0);
    expect(HelperBadge.getWatchDurationProgress(-1).currentValue, 0);
    expect(maxed.currentTitle, 'Time Bender');
    expect(maxed.nextTitle, maxed.currentTitle);
    expect(maxed.currentValue, 400 * hour);
    expect(maxed.targetValue, 400 * hour);
    expect(maxed.percent, 100);
  });

  test('Badge percentage never leaves the 0 to 100 range', () {
    expect(BadgeProgress(currentTitle: 'a', nextTitle: 'b', currentValue: 5, targetValue: 0, isMaxLevel: false).percent, 0);
    expect(BadgeProgress(currentTitle: 'a', nextTitle: 'b', currentValue: 5, targetValue: -10, isMaxLevel: false).percent, 0);
    expect(BadgeProgress(currentTitle: 'a', nextTitle: 'b', currentValue: 900, targetValue: 100, isMaxLevel: false).percent, 100);
    expect(BadgeProgress(currentTitle: 'a', nextTitle: 'b', currentValue: -5, targetValue: 100, isMaxLevel: false).percent, 0);
    expect(BadgeProgress(currentTitle: 'a', nextTitle: 'b', currentValue: 0, targetValue: 0, isMaxLevel: true).percent, 100);
  });

  test('Collection tooltips mention the real count and match the unlocked tier', () {
    expect(HelperBadge.getBadgeTotVidTooltip(0), '~');
    const cases = {
      50: 'Newbie',
      150: 'Jav Lover',
      250: 'Jav Hunter',
      350: 'Nolep',
      450: 'Degenerate',
      750: 'Freak',
      2000: 'Nolep x_x',
    };
    cases.forEach((count, fragment) {
      final tooltip = HelperBadge.getBadgeTotVidTooltip(count);
      expect(tooltip, contains('$count'), reason: 'count $count');
      expect(tooltip, contains(fragment), reason: 'count $count');
    });
  });

  test('Collection icons stay hidden while empty and use the tier colors afterwards', () {
    expect(HelperBadge.getBadgeTotVidIcons(0), isNot(isA<HugeIcon>()));

    for (final count in [1, 100, 101, 200, 201, 300, 301, 400, 401, 1000, 1001]) {
      final widget = HelperBadge.getBadgeTotVidIcons(count);
      expect(widget, isA<HugeIcon>(), reason: 'count $count');
      expect((widget as HugeIcon).size, AppStyle.iconSize, reason: 'count $count');
      expect(widget.color, isNotNull, reason: 'count $count');
      expect(widget.icon, isNotEmpty);
    }

    final low = HelperBadge.getBadgeTotVidIcons(50) as HugeIcon;
    final mid = HelperBadge.getBadgeTotVidIcons(150) as HugeIcon;
    final high = HelperBadge.getBadgeTotVidIcons(900) as HugeIcon;
    final beyond = HelperBadge.getBadgeTotVidIcons(1001) as HugeIcon;
    expect(low.icon, isNot(mid.icon));
    expect(high.icon, isNot(beyond.icon));
    expect(HelperBadge.getBadgeTotVidIcons(500).runtimeType, high.runtimeType);
  });
}
