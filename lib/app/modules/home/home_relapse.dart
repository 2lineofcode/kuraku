import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../data/database/db_relapse.dart';
import '../../data/models/relapse_entity.dart';
import 'page_settings/page_settings_controller.dart';

mixin HomeRelapse {
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
                Icon(CupertinoIcons.thermometer, size: 18).pOnly(right: 12, left: 8),
                'Relapse Timeline ($countAll)'.text.bold.make(),
                Spacer(),
                IconButton(
                  icon: Icon(CupertinoIcons.add, size: 18),
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
                return ListTile(
                  title: '${item['date']}'.text.size(12).bold.make(),
                  subtitle: '${item['count']} times'.text.size(10).minFontSize(10).make(),
                );
              },
            ).expand(),
          ],
        ).p8(),
      ),
    );
  }


  static Future<void> _onRelapse() async {
    await DBRelapse.add(Relapse(date: DateTime.now().toStringEx(format: 'yyyy-MM-dd')));
    await Get.find<PageSettingsController>().onInit();
  }
}
