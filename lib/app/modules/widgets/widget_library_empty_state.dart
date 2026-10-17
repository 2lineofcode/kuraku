import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/app_color.dart';
import 'widget_controls.dart';

class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DottedBorder(
          options: RoundedRectDottedBorderOptions(
            radius: const Radius.circular(12), dashPattern: const [6, 5],
            color: AppColor.muted.withAlpha(150), strokeWidth: 1.2, padding: EdgeInsets.zero,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            decoration: BoxDecoration(color: AppColor.hover.withAlpha(40), borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 36, color: AppColor.muted),
              const SizedBox(height: 12),
              Text('Drop a folder here'.tr, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColor.text)),
              const SizedBox(height: 6),
              Text('Add videos or image albums to your library.'.tr, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColor.muted)),
              const SizedBox(height: 16),
              AppButton(variant: AppButtonVariant.outlined, onPressed: onAdd, child: Text('Add folder'.tr)),
            ]),
          ),
        ),
      ),
    ));
  }
}
