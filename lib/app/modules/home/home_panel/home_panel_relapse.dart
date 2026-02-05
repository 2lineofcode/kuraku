import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/const.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/models/activity_entity.dart';
import '../../../utils/helper_misc.dart';
import '../home_controller.dart';
import '../page_settings/page_settings_controller.dart';

/// A mixin for managing relapse-related functionalities.
mixin HomePanelRelapse {
  /// Displays the relapse timeline as an overlay panel.
  /// This panel shows a list of relapse dates and the total count.
  static Future<void> open() async {
    final relapse = <Activity>[].obs;
    final countWeek = 0.obs;
    final countMonth = 0.obs;
    final countAll = 0.obs;

    relapse.value = await DBActivity.getAllRelapse();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfMonth = DateTime(today.year, today.month, 1);

    var weekTotal = 0;
    var monthTotal = 0;
    var allTotal = 0;

    for (final item in relapse) {
      final rawDate = item.content;
      if (rawDate.isNullOrEmpty) continue;
      final date = rawDate!.toDateEx(format: kYMd);
      final times = item.times ?? 1;

      allTotal += times;
      if (!date.isBefore(startOfWeek)) {
        weekTotal += times;
      }
      if (!date.isBefore(startOfMonth)) {
        monthTotal += times;
      }
    }

    countWeek.value = weekTotal;
    countMonth.value = monthTotal;
    countAll.value = allTotal;

    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
        child: VStack(
          [
            HStack(
              [
                Icon(UIconsPro.regularRounded.banana, size: 16).pOnly(right: 12, left: 8),
                'Relapse'.text.bold.make(),
                Spacer(),
                IconButton(
                  icon: Icon(UIconsPro.regularRounded.refresh, size: 13).tooltip('Relapse :('),
                  onPressed: () async {
                    await _onRelapse();
                    await Overlayment.dismissLast();
                  },
                ),
              ],
            ),
            Divider(),
            
            relapse.value.isEmpty
                ? ExUiErrorOrEmpty(
                    illustration: Icon(UIconsPro.regularRounded.flame, size: 64).pOnly(bottom: 12),
                    title: 'Still dont have data',
                    message: 'You can click `+` if you masturbate',
                  ).expand()
                : TimelineTheme(
                    data: TimelineThemeData(
                      direction: Axis.vertical,
                      color: Colors.white,
                      connectorTheme: ConnectorThemeData(color: Colors.white24, thickness: 1.6),
                      indicatorTheme: IndicatorThemeData(color: Colors.white, size: 18),
                    ),
                    child: Timeline.tileBuilder(
                      physics: BouncingScrollPhysics(),
                      padding: EdgeInsets.only(left: 6, right: 10, bottom: 8),
                      builder: TimelineTileBuilder.connected(
                        itemExtent: 56,
                        itemCount: relapse.length,
                        contentsAlign: ContentsAlign.basic,
                        nodePositionBuilder: (_, __) => 0.01,
                        indicatorBuilder: (context, index) {
                          final times = relapse[index].times ?? 1;
                          return DotIndicator(
                            size: 18,
                            color: times > 1 ? Vx.red700 : AppColor.selected,
                            child: times > 1 ? '${times}x'.text.size(8).minFontSize(8).white.makeCentered() : Icon(UIconsPro.regularRounded.circle_dashed, size: 11, color: Colors.white),
                          );
                        },
                        connectorBuilder: (context, index, type) {
                          final isLast = index == relapse.length - 1;
                          return isLast && type == ConnectorType.end
                              ? TransparentConnector()
                              : SolidLineConnector(thickness: 1.6, color: Colors.white24);
                        },
                        contentsBuilder: (context, index) {
                          final item = relapse[index];
                          final times = item.times ?? 1;
                          return HStack(
                            [
                              VStack(
                                [
                                  HelperMisc.timeAgo(kYMd, item.content ?? '').text.size(11).color(Colors.white).make(),
                                  'Masturbate'.text.size(10).neutral300.minFontSize(10).make(),
                                ],
                                crossAlignment: CrossAxisAlignment.start,
                              ).expand(),
                              '$times Times'.text.size(11).minFontSize(11).white.make().pSymmetric(h: 8, v: 3).color(times > 1 ? Vx.red700 : AppColor.selected).cornerRadius(90),
                              IconButton(
                                icon: Icon(UIconsPro.regularRounded.minus_circle, size: 12, color: Colors.white),
                                tooltip: 'Delete 1 Record',
                                onPressed: () async {
                                  await Overlayment.dismissLast();
                                  await DBActivity.deleteRelapseByDateLimitOne(item.content ?? '');
                                  await DBActivity.getCountRelapseToday();
                                  Get.find<HomeController>().isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();
                                  Get.appUpdate();
                                },
                              )
                            ],
                            alignment: MainAxisAlignment.start,
                          ).pOnly(left: 12);
                        },
                      ),
                    ),
                  ).expand(),
            Container(
              width: double.infinity,
              decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4, fillColor: Colors.black),
              child: VStack([
                'This Week: ${countWeek.value}'.text.size(12).make(),
                'This Month: ${countMonth.value}'.text.size(12).make(),
                'All Time: ${countAll.value}'.text.size(12).make().pOnly(top: 8),
              ]).p12(),
            ).pSymmetric(v: 12),
          ],
        ).p8(),
      ),
    );
  }

  /// Adds a new relapse entry to the database and updates the UI.
  static Future<void> _onRelapse() async {
    await DBActivity.addRelapse(date: DateTime.now());
    await Get.find<PageSettingsController>().onRefresh();

    await DBActivity.getCountRelapseToday();
    Get.find<HomeController>().isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();
    Get.appUpdate();
  }
}
