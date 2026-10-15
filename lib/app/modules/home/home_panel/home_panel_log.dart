import 'dart:convert';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../home_controller.dart';

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
        position: const Offset(16, 16),
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
        child: Builder(builder: (context) {
          AppColor.dependOn(context);
          final size = MediaQuery.sizeOf(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return SizedBox(
            width: math.min(400, size.width - 32),
            height: math.min(400, size.height - 32),
            child: Material(color: AppColor.panel, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('APP LOG'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(child: Obx(() => Text('${_appLogRuntime.length}',
                    style: TextStyle(fontSize: 11, color: AppColor.muted)))),
                  AppIconButton(
                    tooltip: 'Close'.tr,
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize),
                    onPressed: () => Overlayment.dismissLast(),
                  ),
                ]),
                Divider(height: 16, thickness: .5, color: AppColor.border),
                Expanded(child: Obx(() {
                  if (_appLogRuntime.isEmpty) return Center(child: Text('No app logs'.tr,
                    style: TextStyle(fontSize: 12, color: AppColor.muted)));
                  return ListView.separated(
                    itemCount: _appLogRuntime.length,
                    separatorBuilder: (_, _) => Divider(height: 1, thickness: .5, color: AppColor.border),
                    itemBuilder: (_, index) {
                      final item = _appLogRuntime[index];
                      final level = item.type?.toUpperCase() == 'WARNING' ? 'WARN' : (item.type ?? '-').toUpperCase();
                      final color = switch (level) {
                        'DEBUG' => dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                        'WARN' => dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                        'ERROR' => Theme.of(context).colorScheme.error,
                        'INFO' || 'OK' || 'SUCCESS' => AppColor.success,
                        _ => AppColor.muted,
                      };
                      final date = DateTime.tryParse(item.createdAt ?? '');
                      final time = date == null ? item.createdAt ?? '-' :
                        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
                      return InkWell(
                        borderRadius: BorderRadius.circular(AppStyle.radius),
                        onTap: () => HelperMisc.copyToClipboard(item.content ?? ''),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(time, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: AppColor.muted))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                                child: Text(level, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Tooltip(message: item.content ?? '', child: Text(item.content ?? '-',
                              maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: AppColor.text))),
                          ])),
                      );
                    },
                  );
                })),
                Divider(height: 16, thickness: .5, color: AppColor.border),
                Row(children: [
                  Obx(() => AppButton(label: 'Clear'.tr, height: 30,
                    onPressed: _appLogRuntime.isEmpty ? null : clear)),
                  const Spacer(),
                  AppButton(label: 'Open all'.tr, height: 30, variant: AppButtonVariant.tonal, onPressed: () async {
                    await Overlayment.dismissLast();
                    await Get.find<HomeController>().onOpenSettingsAppLog();
                  }),
                ]),
              ]),
            )),
          );
        }),
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
    if (_appLogRuntime.length > 1000) _appLogRuntime.removeRange(1000, _appLogRuntime.length);
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
