import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_color.dart';

class DownloadMethodDialog extends StatelessWidget {
  const DownloadMethodDialog({super.key, required this.onSelected});

  final ValueChanged<String?> onSelected;

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
              ('native', 'Native'.tr, 'Download in JavIt'.tr, Icons.download_rounded),
              ('downie', 'Downie'.tr, 'Send to Downie'.tr, Icons.open_in_new_rounded),
              ('url', 'Just Open URL'.tr, 'Open in your default browser'.tr, Icons.language_rounded),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColor.text,
                    backgroundColor: AppColor.container,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: AppColor.border),
                  ),
                  onPressed: () => onSelected(option.$1),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColor.accent.withAlpha(18), borderRadius: BorderRadius.circular(8)),
                        child: Icon(option.$4, size: 20, color: AppColor.accent),
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
                      Icon(Icons.chevron_right_rounded, size: 18, color: AppColor.muted),
                    ],
                  ),
                ),
              ),
            Divider(height: 16, color: AppColor.border),
            TextButton(
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
