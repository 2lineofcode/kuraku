import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_dependencies.dart';
import '../../core/app_setting.dart';
import '../../core/app_translations.dart';
import 'widget_controls.dart';
import 'widget_surfaces.dart';

Future<List<DependencyStatus>> showStartupDependencyGuide({Future<List<DependencyStatus>> Function()? check}) async {
  final performCheck = check ?? () => AppDependencies.shared.checkAll(Get.find<AppSettingService>().bundledAssetsPath);
  var results = await performCheck();
  if (results.every((result) => result.ready)) return results;
  await Get.dialog(DependencyGuide(
    issues: results.where((result) => !result.ready).toList(),
    check: () async {
      results = await performCheck();
      return results;
    },
    onReady: () => Get.back(),
    onContinue: () => Get.back(),
  ));
  return results;
}

class DependencyGuide extends StatefulWidget {
  const DependencyGuide({super.key, required this.issues, required this.check, required this.onReady, this.onContinue});
  final List<DependencyStatus> issues;
  final Future<List<DependencyStatus>> Function() check;
  final VoidCallback onReady;
  final VoidCallback? onContinue;

  @override
  State<DependencyGuide> createState() => _DependencyGuideState();
}

class _DependencyGuideState extends State<DependencyGuide> {
  late List<DependencyStatus> _issues = widget.issues;
  bool _checking = false;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      final results = await widget.check();
      if (!mounted) return;
      final issues = results.where((result) => !result.ready).toList();
      if (issues.isEmpty) { widget.onReady(); return; }
      setState(() => _issues = issues);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text('Install missing dependencies'.tr),
    content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text((widget.onContinue == null
        ? 'Restore the dependencies below, then check again to open KuraKu.'
        : 'Only the features listed below are affected. Install what you need, then check again.').tr),
      const SizedBox(height: 8),
      for (final issue in _issues) Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(issue.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Used by: @{feature}'.trNamed({'feature': issue.feature.tr}), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(issue.fix.tr, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    ]),
    actions: [
      if (widget.onContinue != null) AppButton(onPressed: _checking ? null : widget.onContinue, child: Text('Continue'.tr)),
      AppButton(onPressed: _checking ? null : _recheck,
        child: _checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Check again'.tr)),
    ],
  );
}
