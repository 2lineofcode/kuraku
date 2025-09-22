import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import '../../core/const.dart';
import '../../data/database/db_relapse.dart';
import '../../data/models/relapse_entity.dart';
import 'page_settings/page_settings_controller.dart';

/// A mixin for managing relapse-related functionalities.
mixin HomeRelapse {

  /// Displays the relapse timeline as an overlay panel.
  /// This panel shows a list of relapse dates and the total count.
  static Future<void> openMenuRelapse() async {
    final relapse = <Map<String, dynamic>>[].obs;
    final countAll = 0.obs;

    relapse.value = await DBRelapse.getAll();
    countAll.value = await DBRelapse.getCount();

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
                Icon(UIconsPro.regularRounded.calendar_minus, size: 16).pOnly(right: 12, left: 8),
                'Relapse Timeline ($countAll)'.text.bold.make(),
                Spacer(),
                IconButton(
                  icon: Icon(UIconsPro.regularRounded.plus, size: 13),
                  onPressed: () async {
                    await _onRelapse();
                    await Overlayment.dismissLast();
                  },
                ),
              ],
            ),
            Divider(),
            ListView.separated(
              itemCount: relapse.length,
              separatorBuilder: (context, index) => Divider(),
              itemBuilder: (context, index) {
                final item = relapse[index];
                return HStack([
                  Icon(UIconsPro.solidRounded.minus, size: 12).pOnly(left: 8, right: 12),
                  VStack([
                    '${item['date'].toString().reformatDate(from: kYMd, to: kMdY)}'.text.size(12).bold.make(),
                    '${item['date'].toString().ago(format: kYMd)}'.text.size(10).neutral400.minFontSize(10).make(),
                  ]),
                  Spacer(),
                  '${item['count']} times'.text.size(10).minFontSize(10).make().w(40).pSymmetric(h: 5, v: 2).color(AppColor.selected),
                ]);
              },
            ).expand(),
          ],
        ).p8(),
      ),
    );
  }

  /// Adds a new relapse entry to the database and updates the UI.
  static Future<void> _onRelapse() async {
    await DBRelapse.add(Relapse(date: DateTime.now().toStringEx(format: kYMd)));
    await Get.find<PageSettingsController>().onInit();
  }
}
