import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import 'widget_controls.dart';
import 'widget_style.dart';

class DownloadMethodDialog extends StatelessWidget {
  const DownloadMethodDialog({super.key, required this.onSelected, required this.defaultEngine, this.hasSourceUrl = false});

  final ValueChanged<({String method, String? engine})?> onSelected;
  final String defaultEngine;
  final bool hasSourceUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Download'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColor.text)),
            const SizedBox(height: 4),
            Text('Choose how to open this video'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)),
            const SizedBox(height: 20),
            for (final option in [
              ('native', 'Native'.tr, 'Download in KuraKu'.tr, HugeIcons.strokeRoundedDownload01),
              if (Platform.isMacOS) ('downie', 'Downie'.tr, 'Send to Downie'.tr, HugeIcons.strokeRoundedLinkSquare02),
              ('url', 'Just Open URL'.tr, 'Open in your default browser'.tr, HugeIcons.strokeRoundedGlobe02),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MenuAnchor(
                  animated: false,
                  consumeOutsideTap: true,
                  menuChildren: [
                    for (final engine in [if (hasSourceUrl) null, ...AppPref.searchEngines])
                      MenuItemButton(
                        onPressed: () => onSelected((method: option.$1, engine: engine)),
                        leadingIcon: HugeIcon(
                          icon: engine == (hasSourceUrl ? null : defaultEngine) ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedCircle,
                          size: AppStyle.iconSize,
                        ),
                        child: Text(engine ?? 'Original URL'.tr),
                      ),
                  ],
                  builder: (context, menu, child) => AppButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColor.text,
                      backgroundColor: AppColor.container,
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: AppColor.border),
                    ),
                    onPressed: () => onSelected((method: option.$1, engine: hasSourceUrl ? null : defaultEngine)),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: AppColor.muted.withAlpha(18), borderRadius: BorderRadius.circular(8)),
                          child: HugeIcon(icon: option.$4, size: AppStyle.iconSize, color: AppColor.text).p(6),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(option.$3, style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: AppColor.muted)),
                            ],
                          ),
                        ),
                        AppIconButton(
                          key: ValueKey('download-engine-${option.$1}'),
                          tooltip: 'Search Engine'.tr,
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: AppStyle.iconSize, color: AppColor.muted),
                          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Divider(height: 16, color: AppColor.border),
            AppButton(
              style: TextButton.styleFrom(foregroundColor: AppColor.muted, textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12)),
              onPressed: () => onSelected(null),
              child: Text('Cancel'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
