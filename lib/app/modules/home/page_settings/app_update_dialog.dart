import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../utils/app_updater.dart';
import '../../../utils/helper_toast.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_surfaces.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.release, required this.installedVersion, required this.openLink});

  final AppRelease release;
  final String installedVersion;
  final Future<bool> Function(Uri) openLink;
  static bool _showing = false;

  static Future<void> show({required AppRelease release, required String installedVersion, bool automatic = false}) async {
    if (_showing) return;
    if (automatic && (Get.isDialogOpen == true || Get.isBottomSheetOpen == true)) {
      await HelperToast.info('KuraKu @{version} is available. Open Settings to view the update.'.trNamed({'version': release.version}),
        duration: const Duration(seconds: 8));
      return;
    }
    _showing = true;
    try {
      await Get.dialog(AppUpdateDialog(
        release: release,
        installedVersion: installedVersion,
        openLink: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
      ));
    } finally {
      _showing = false;
    }
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool opening = false;
  bool failed = false;

  Future<void> open(Uri url) async {
    if (opening) return;
    setState(() { opening = true; failed = false; });
    try {
      final opened = await widget.openLink(url);
      if (mounted) setState(() => failed = !opened);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  String get installInstruction {
    if (Platform.isMacOS) return 'Requires Apple Silicon and macOS 26+. After downloading, quit KuraKu, open the DMG, and drag KuraKu to Applications to replace the old app.';
    if (Platform.isLinux && widget.release.assetName?.endsWith('.deb') == true) return 'Built for Ubuntu 22.04 x64. After downloading, quit KuraKu and open the DEB with your package manager to install the update.';
    if (Platform.isWindows) return 'After downloading, quit KuraKu, extract the entire ZIP, and run kuraku.exe from the new folder.';
    return 'After downloading, quit KuraKu, extract the ZIP, and replace the old app with the new version.';
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    return AppDialog(
      maxWidth: 560,
      title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Update available'.tr),
        if (failed) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(liveRegion: true, child: Text('Could not open your browser. Try again or copy this link:'.tr,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error))),
        ),
        if (failed) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(release.releaseUrl.toString(), style: const TextStyle(fontSize: 11))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('KuraKu @{version}'.trNamed({'version': release.version}), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Installed: @{version}'.trNamed({'version': widget.installedVersion}), style: TextStyle(fontSize: 12, color: AppColor.muted)),
        const SizedBox(height: 16),
        if (release.downloadUrl != null) ...[
          Text('The download opens in your browser. Install the update manually when you’re ready.'.tr, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (release.assetName != null) Text(release.assetName!, style: TextStyle(fontSize: 11, color: AppColor.muted)),
          const SizedBox(height: 8),
          Text(installInstruction.tr, style: const TextStyle(fontSize: 12)),
          if (Platform.isMacOS) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
            'This build is unsigned. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway.'.tr,
            style: TextStyle(fontSize: 11, color: AppColor.muted),
          )),
        ] else
          Text('No compatible download was found for this device. Open the release page to see the available packages and instructions.'.tr, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Text('Before installing, use Export Backup in Settings to back up your library and settings.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        const SizedBox(height: 20),
        Text('Release notes'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SelectableText(release.notes.trim().isEmpty ? 'No release notes were provided.'.tr : release.notes, style: const TextStyle(fontSize: 12)),
      ]),
      actions: [
        AppButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close'.tr)),
        AppButton(
          variant: release.downloadUrl == null ? AppButtonVariant.filled : AppButtonVariant.outlined,
          onPressed: opening ? null : () => open(release.releaseUrl),
          child: Text('View release'.tr),
        ),
        if (release.downloadUrl != null) AppButton(
          variant: AppButtonVariant.filled,
          onPressed: opening ? null : () => open(release.downloadUrl!),
          child: Text('Download update'.tr),
        ),
      ],
    );
  }
}
