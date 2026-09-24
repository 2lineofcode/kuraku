import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/const.dart';
import '../../../utils/helper.dart';

mixin HomePanelAppLog {

  static final _appLogRuntime = <AppLogRuntime>[].obs;
  static RxList<AppLogRuntime> get appLogRuntime => _appLogRuntime;

  static Future<void> open() async {
    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    WidgetsBinding.instance.scheduleFrame();


    await Overlayment.show(
      context: Get.context,
      OverWindow(
        canMove: true,
        position: Offset(50, 50),
        color: AppColor.panel,
        actions: OverlayActions(
          onOpen: () async {
            _appLogRuntime.sort((a, b) {
              final aDate = DateTime.tryParse(a.createdAt ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = DateTime.tryParse(b.createdAt ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
          },
        ),
        child: VStack(
          [
            HStack([
              'APP LOG'.text.bold.make().expand(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.cross, size: 13),
                tooltip: 'Close',
                onPressed: () => Overlayment.dismissLast(),
              )
            ]).pOnly(bottom: 12),

            Obx(
              () => ListView.separated(
                itemCount: _appLogRuntime.length,
                separatorBuilder: (context, index) => Divider(color: AppColor.border),
                itemBuilder: (context, index) {
                  final item = _appLogRuntime[index];

                  var tColor = AppColor.text;
                  if (item.type?.toLowerCase() == 'error') tColor = Vx.red400;
                  else if (item.type?.toLowerCase() == 'warning') tColor = Vx.yellow400;
                  else if (item.type?.toLowerCase() == 'info') tColor = Vx.blue400;
                  else if (item.type?.toLowerCase() == 'debug') tColor = Vx.gray400;
                  else tColor = Vx.green400;

                  return HStack(
                    [
                      // icon
                      Icon(UIconsPro.regularRounded.circle_dashed, size: 11).pOnly(right: 12),
                      VStack([
                        HStack([
                          '${item.createdAt?.reformatDate(to: kHms)}'.text.gray400.size(9).minFontSize(10).make().expand(),
                          '${item.type}'.text.color(tColor).size(9).minFontSize(10).make(),
                        ]),
                        '${item.content}'.text.size(11).minFontSize(12).make().onTap((){
                          HelperMisc.copyToClipboard(item.content);
                        }),
                      ]).expand(),
                    ],
                  );
                },
              ).expand(),
            ),

            // Spacer(),
            ExButtonText(
              label: 'Clear',
              height: 32,
              width: double.infinity,
              onPressed: () => clear(),
            ),
          ],
        ).p12().wh(300, 300),
      ),
    );
  }

  static Future<void> add(String type, String content) async {
    _appLogRuntime.insert(0,
      AppLogRuntime(
        type: type,
        content: content,
        createdAt: DateTime.now().toStringEx(),
      ),
    );
  }

  static void clear() {
    // Overlayment.dismissLast();
    _appLogRuntime.clear();
  }
}

class AppLogRuntime {
  String? id;
  String? type;
  String? content;
  String? createdAt;

  AppLogRuntime({this.id, this.type, this.content, this.createdAt});

  AppLogRuntime.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    type = json['type'];
    content = json['content'];
    createdAt = json['created_at'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['type'] = type;
    data['content'] = content;
    data['created_at'] = createdAt;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
