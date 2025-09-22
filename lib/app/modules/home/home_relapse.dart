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

    final oneWeekAgo = DateTime.now().subtract(Duration(days: 7));
    final oneMonthAgo = DateTime(DateTime.now().year, DateTime.now().month - 1, DateTime.now().day);

    countWeek.value = await DBActivity.getAll(
      where: 'type = ? AND DATE(content) >= DATE(?) AND DATE(content) <= DATE(?)',
      whereArgs: [kActivityTypeRelapse, oneWeekAgo.toStringEx(format: kYMd), DateTime.now().toStringEx(format: kYMd)],
    ).then((value) => value.length);

    countMonth.value = await DBActivity.getAll(
      where: 'type = ? AND DATE(content) >= DATE(?) AND DATE(content) <= DATE(?)',
      whereArgs: [kActivityTypeRelapse, oneMonthAgo.toStringEx(format: kYMd), DateTime.now().toStringEx(format: kYMd)],
    ).then((value) => value.length);

    countAll.value = await DBActivity.getAll(where: 'type = ?', whereArgs: [kActivityTypeRelapse]).then((value) => value.length);

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
                  icon: Icon(UIconsPro.regularRounded.refresh, size: 13),
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
          : ListView.separated(
              itemCount: relapse.length,
              separatorBuilder: (context, index) => Divider(),
              itemBuilder: (context, index) {
                final item = relapse[index];
                return HStack([
                  Icon(UIconsPro.regularRounded.circle_dashed, size: 10).pOnly(left: 8, right: 12),
                  VStack([
                    '${item.content!.toDateEx(format: kYMd).isSameDay(DateTime.now()) 
                      ? 'Today' 
                      : HelperMisc.timeAgo(kYMd, item.content ?? '')}'.text.size(12).bold.make(),
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
                'This Week: $countWeek'.text.size(12).make(),
                'This Month: $countMonth'.text.size(12).make(),
                'All Time: $countAll'.text.size(12).make().pOnly(top: 8),
              ]
              ).p12(),
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
  }
}
