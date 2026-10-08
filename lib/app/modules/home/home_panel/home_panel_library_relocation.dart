import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/library_relocation.dart';
import '../../../data/models/library_entity.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';

class LibraryRelocationDialog extends StatefulWidget {
  const LibraryRelocationDialog({super.key, required this.library, required this.onApply});

  final Library library;
  final Future<void> Function(LibraryRelocation) onApply;

  @override
  State<LibraryRelocationDialog> createState() => _LibraryRelocationDialogState();
}

class _LibraryRelocationDialogState extends State<LibraryRelocationDialog> {
  final _path = TextEditingController();
  LibraryRelocation? _preview;
  String? _error;
  bool _loading = false, _applying = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    if (_loading || _applying) return;
    setState(() => _loading = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || !mounted) return;
      setState(() { _path.text = path; _preview = null; _error = null; });
      final preview = await LibraryRelocation.preview(widget.library, path);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? '${e.message}'.tr : 'Could not read the selected folder.'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    if (_loading || _applying || _preview?.canApply != true) return;
    setState(() { _applying = true; _error = null; });
    try {
      await widget.onApply(_preview!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() {
        _preview = null;
        _error = e is StateError ? '${e.message}'.tr : 'Relocation failed. No paths were changed. Build a new preview.'.tr;
      });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _status(RelocationStatus status) => switch (status) {
    RelocationStatus.matched => 'Matched'.tr,
    RelocationStatus.unverified => 'Path match'.tr,
    RelocationStatus.missing => 'Missing'.tr,
    RelocationStatus.conflict => 'Conflict'.tr,
  };

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final preview = _preview;
    return PopScope(canPop: !_applying, child: AppDialog(
      title: Text('Relocate Library'.tr),
      content: DefaultTextStyle.merge(style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.text),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.library.alias ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        CupertinoFormRow(
          padding: EdgeInsets.zero,
          prefix: SizedBox(width: 96, child: Text('Current root'.tr,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.text))),
          child: SizedBox(width: double.infinity,
            child: SelectableText(widget.library.rootFolder ?? '', style: const TextStyle(fontSize: 12))),
        ),
        const SizedBox(height: 8),
        CupertinoFormRow(
          padding: EdgeInsets.zero,
          prefix: SizedBox(width: 96, child: Text('New root'.tr,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.text))),
          child: AppTextField(
            controller: _path, placeholder: '<Select Path>'.tr, readOnly: true,
            enabled: !_loading && !_applying, onTap: _pickFolder,
            suffix: AppIconButton(
              tooltip: 'Select folder'.tr,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: AppStyle.iconSize),
              onPressed: _loading || _applying ? null : _pickFolder,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Move files first, then select the new root. Relative paths are preserved; missing records keep their data at the new paths.'.tr,
          style: TextStyle(fontSize: 11, color: AppColor.muted)),
        if (_loading) ...[const SizedBox(height: 12), Text('Building preview…'.tr)],
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
        if (preview != null) ...[
          const SizedBox(height: 12),
          Text('Preview: @{matched} matched • @{unverified} path matches • @{missing} missing • @{conflicts} conflicts'.trNamed({
            'matched': '${preview.count(RelocationStatus.matched)}', 'unverified': '${preview.count(RelocationStatus.unverified)}',
            'missing': '${preview.count(RelocationStatus.missing)}', 'conflicts': '${preview.count(RelocationStatus.conflict)}',
          }), style: const TextStyle(fontSize: 12)),
          if (preview.count(RelocationStatus.unverified) > 0) ...[
            const SizedBox(height: 8),
            Text('Path matches have no original fingerprint. Check these paths before applying.'.tr,
              style: TextStyle(fontSize: 11, color: AppColor.muted)),
          ],
          if (!preview.canApply) ...[const SizedBox(height: 8), Text('Resolve conflicts and match at least one file before applying.'.tr)],
          if (preview.entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(height: 220, child: ListView.separated(
              itemCount: preview.entries.length,
              separatorBuilder: (_, _) => Divider(height: 16, thickness: .5, color: AppColor.border),
              itemBuilder: (_, index) {
                final entry = preview.entries[index];
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(_status(entry.status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: entry.status == RelocationStatus.conflict ? Theme.of(context).colorScheme.error : AppColor.muted)),
                  const SizedBox(height: 4),
                  SelectableText('${entry.oldPath}\n→ ${entry.newPath}', style: const TextStyle(fontSize: 12)),
                  if (entry.reason != null) Text(entry.reason!.tr, style: const TextStyle(fontSize: 11)),
                ]);
              },
            )),
          ],
        ],
      ])),
      actions: [
        AppButton(label: 'Cancel'.tr, variant: AppButtonVariant.text,
          onPressed: _applying ? null : () => Navigator.of(context).pop()),
        AppButton(label: _applying ? 'Applying…'.tr : 'Apply'.tr,
          onPressed: _loading || _applying || preview?.canApply != true ? null : _apply),
      ],
    ));
  }
}
