import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import '../../core/const.dart';
import '../../data/database/db_activity.dart';
import '../../data/models/activity_entity.dart';
import '../../utils/helper_misc.dart';
import 'home_controller.dart';
import 'page_settings/page_settings_controller.dart';

/// A mixin for managing relapse-related functionalities.
mixin HomeRelapse {
  /// Displays the relapse timeline as an overlay panel.
  /// This panel shows a list of relapse dates and the total count.
  static Future<void> openMenuRelapse() async {
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

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerRight,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
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
            relapse.value.isNotEmpty
                ? 'Last Relapse: ${relapse[0].content!.toDateEx(format: kYMd).isSameDay(DateTime.now()) ? 'Today' : '${HelperMisc.timeAgo(kYMd, relapse[0].content ?? '')}'}'
                    .text
                    .makeCentered()
                    .pSymmetric(v: 8)
                    .color(AppColor.border)
                    .cornerRadius(90)
                    .pOnly(top: 8, bottom: 16)
                : 0.heightBox,

            relapse.value.isEmpty
                ? ExUiErrorOrEmpty(
                    illustration: Icon(UIconsPro.regularRounded.flame, size: 64).pOnly(bottom: 12),
                    title: 'Still dont have data',
                    message: 'You can click `+` if you masturbate',
                  ).expand()
                : ListView.separated(
                    itemCount: relapse.length,
                    separatorBuilder: (context, index) => Divider(),
                    itemBuilder: (context, index) {
                      final item = relapse[index];
                      return HStack([
                        Icon(UIconsPro.regularRounded.circle_dashed, size: 10).pOnly(left: 8, right: 12),
                        VStack([
                          '${item.content!.toDateEx(format: kYMd).isSameDay(DateTime.now()) ? 'Today' : HelperMisc.timeAgo(kYMd, item.content ?? '')}'.text.size(12).bold.make(),
                          'Masturbate'.text.size(10).neutral400.minFontSize(10).make(),
                        ]),
                        Spacer(),
                        '${item.times} Times'.text.size(11).minFontSize(11).make().w(45).pSymmetric(h: 8, v: 2).color(item.times! > 1 ? Vx.red800 : AppColor.selected).cornerRadius(4),
                      ]);
                    },
                  ).expand(),
            Container(
              width: double.infinity,
              decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
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
    await DBActivity.add(
      Activity(
        type: kActivityTypeRelapse,
        content: DateTime.now().toStringEx(format: kYMd),
      ),
    );
    await Get.find<PageSettingsController>().onInit();

    await DBActivity.getCountRelapseToday();
    Get.find<HomeController>().isDangerMode.value = await DBActivity.getCountRelapseToday() >= 2;
    Get.appUpdate();
  }
}
