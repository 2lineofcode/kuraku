import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import 'page_download_controller.dart';

class PageDownloadDialog extends StatefulWidget {
  const PageDownloadDialog({super.key, required this.controller});
  final PageDownloadController controller;

  @override
  State<PageDownloadDialog> createState() => _PageDownloadDialogState();
}

class _PageDownloadDialogState extends State<PageDownloadDialog> {
  PageDownloadController get controller => widget.controller;
  bool _optionsExpanded = false;
  bool _logExpanded = false;

  Widget _field(String label, TextEditingController field, {bool enabled = true, bool number = false, FocusNode? focusNode}) => Tooltip(
    message: label,
    child: Semantics(label: label, child: AppTextField(
      controller: field, focusNode: focusNode, enabled: enabled, placeholder: label,
      style: TextStyle(color: AppColor.text),
      decoration: const InputDecoration(border: InputBorder.none),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      keyboardType: number ? TextInputType.number : TextInputType.text,
    )),
  );

  Widget _number(String label, TextEditingController field, bool enabled) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 10, color: AppColor.muted)),
    const SizedBox(height: 4),
    _field(label, field, enabled: enabled, number: true),
  ]));

  Widget _row(String label, Widget child) => CupertinoFormRow(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    prefix: SizedBox(width: 76, child: Text(label, style: TextStyle(fontSize: 11, color: AppColor.muted))),
    child: child,
  );

  Widget _disclosure(String label, bool expanded, VoidCallback toggle) => CupertinoButton(
    padding: const EdgeInsets.symmetric(vertical: 10), minimumSize: const Size(0, 32),
    onPressed: toggle,
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: AppColor.text))),
      HugeIcon(icon: expanded ? HugeIcons.strokeRoundedArrowUp01 : HugeIcons.strokeRoundedArrowDown01,
        size: AppStyle.iconSize, color: AppColor.muted),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: CupertinoPopupSurface(child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Padding(padding: const EdgeInsets.all(12), child: Obx(() {
          controller.jobRevision.value;
          final job = controller.job;
          final running = job.running;
          final extract = controller.mode.value == 'extract';
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Download'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              Tooltip(message: 'Close download dialog'.tr, child: CupertinoButton(
                padding: EdgeInsets.zero, minimumSize: const Size.square(AppStyle.iconTarget),
                onPressed: () => Navigator.of(context).pop(),
                child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: AppColor.muted),
              )),
            ]),
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              IgnorePointer(ignoring: running, child: Opacity(opacity: running ? .5 : 1, child: CupertinoSlidingSegmentedControl<String>(
                groupValue: controller.mode.value,
                children: {
                  'extract': Text('Website'.tr, style: const TextStyle(fontSize: 11)),
                  'auto': Text('Auto'.tr, style: const TextStyle(fontSize: 11)),
                  'hls': const Text('HLS', style: TextStyle(fontSize: 11)),
                  'file': Text('File'.tr, style: const TextStyle(fontSize: 11)),
                  'youtube': const Text('YouTube', style: TextStyle(fontSize: 11)),
                },
                onValueChanged: running ? (_) {} : (value) { if (value != null) controller.mode.value = value; },
              ))),
              const SizedBox(height: 12),
              CupertinoFormSection.insetGrouped(
                margin: EdgeInsets.zero, backgroundColor: Colors.transparent,
                children: [
                  _row('URL'.tr, _field('URL'.tr, controller.tecUrl, enabled: !running, focusNode: controller.fnDownloadUrl)),
                  _row('Save to folder'.tr, Row(children: [
                    Expanded(child: _field('Save to folder'.tr, controller.tecDirectory, enabled: !running)),
                    Tooltip(message: 'Choose output folder'.tr, child: CupertinoButton(
                      padding: EdgeInsets.zero, minimumSize: const Size.square(AppStyle.iconTarget),
                      onPressed: running ? null : controller.pickDownloadDirectory,
                      child: const HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: AppStyle.iconSize),
                    )),
                  ])),
                  _row('Filename'.tr, _field(extract ? 'Filename (optional · use page title)'.tr : 'Filename'.tr,
                    controller.tecFilename, enabled: !running)),
                ],
              ),
              if (extract) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Play the video in Chrome, then choose its media here.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))),
              if (!running) ...[
                _disclosure('Options'.tr, _optionsExpanded, () => setState(() => _optionsExpanded = !_optionsExpanded)),
                if (_optionsExpanded) ...[
                  Row(children: [
                    if (['extract', 'auto', 'hls'].contains(controller.mode.value)) ...[
                      _number('Workers (1–64)'.tr, controller.tecConcurrency, true),
                      const SizedBox(width: 8),
                    ],
                    _number('Retries (0–10)'.tr, controller.tecRetries, true),
                    const SizedBox(width: 8),
                    _number('Timeout (s)'.tr, controller.tecTimeout, true),
                  ]),
                  const SizedBox(height: 8),
                  _field('Referer (optional)'.tr, controller.tecReferer),
                  if (!extract) ...[const SizedBox(height: 8), _field('User-Agent (optional)'.tr, controller.tecUserAgent)],
                  if (extract) ...[
                    Row(children: [
                      Expanded(child: Text('Background capture'.tr, style: const TextStyle(fontSize: 11))),
                      CupertinoSwitch(value: controller.headless.value, onChanged: (value) => controller.headless.value = value),
                    ]),
                    if (controller.headless.value) ...[
                      _field('Capture duration (seconds)'.tr, controller.tecCaptureDuration, number: true),
                      const SizedBox(height: 8),
                      _field('Play button selector (optional)'.tr, controller.tecPlaySelector),
                    ],
                    Row(children: [
                      Expanded(child: Text('Allow login / player popups'.tr, style: const TextStyle(fontSize: 11))),
                      CupertinoSwitch(value: controller.allowPopups.value, onChanged: (value) => controller.allowPopups.value = value),
                    ]),
                  ],
                ],
              ],
              if (job.status != 'Ready') ...[
                const SizedBox(height: 8),
                Text(job.status.tr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                if (running) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: job.progress, minHeight: 2)),
                if (job.progressText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(job.progressText, style: const TextStyle(fontSize: 11))),
                if (job.selecting && job.candidates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(job.canSelect ? 'Choose your video; a captured stream can be an ad.'.tr : 'Waiting for capture to finish…'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
                  ConstrainedBox(constraints: const BoxConstraints(maxHeight: 150), child: SingleChildScrollView(child: Column(children: job.candidates.map((candidate) => ListTile(
                    dense: true, visualDensity: VisualDensity.compact, contentPadding: EdgeInsets.zero,
                    title: Text('[${candidate.index}] ${candidate.type}', style: const TextStyle(fontSize: 11)),
                    subtitle: Tooltip(message: candidate.url, child: Text(candidate.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
                    trailing: AppIconButton(tooltip: candidate.supported ? 'Download this media'.tr : 'Unsupported stream'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedDownload01, size: AppStyle.iconSize), onPressed: job.canSelect && candidate.supported ? () async {
                      try {
                        await job.select(candidate);
                      } catch (e) {
                        controller.formError.value = '$e';
                      }
                    } : null),
                  )).toList()))),
                ],
                if (job.status == 'Completed') AppButton(onPressed: () => controller.revealOutput(job.outputPath), icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: AppStyle.iconSize), child: Text(p.basename(job.outputPath), style: const TextStyle(fontSize: 11))),
              ],
              if (job.error.isNotEmpty || controller.formError.value.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText((controller.formError.value.isNotEmpty ? controller.formError.value : job.error).tr, style: const TextStyle(fontSize: 11, color: Colors.redAccent))),
              if (job.logs.isNotEmpty) ...[
                _disclosure('Log'.tr, _logExpanded, () => setState(() => _logExpanded = !_logExpanded)),
                if (_logExpanded) SizedBox(height: 120, width: double.infinity, child: SingleChildScrollView(reverse: true,
                  child: SelectableText(job.logs.join('\n'), style: const TextStyle(fontSize: 10, fontFamily: 'monospace')))),
              ],
            ]))),
            Divider(height: 20, thickness: .5, color: CupertinoColors.separator.resolveFrom(context)),
            Row(children: [
              CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), onPressed: () {
                Navigator.of(context).pop();
                controller.openDownloadLog();
              }, child: Text('History'.tr, style: TextStyle(fontSize: 11))),
              const Spacer(),
              if (running) CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32),
                onPressed: job.cancelled ? null : controller.killProcessDownload,
                child: Text('Cancel download'.tr, style: const TextStyle(fontSize: 12)),
              ) else CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 18), minimumSize: const Size(0, 32),
                borderRadius: BorderRadius.circular(AppStyle.radius),
                onPressed: controller.startDownload,
                child: Text(extract ? 'Capture'.tr : 'Download'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]);
        })),
      )),
    );
  }
}

class PageDownloadHistoryDialog extends StatelessWidget {
  const PageDownloadHistoryDialog({super.key, required this.controller});
  final PageDownloadController controller;

  Widget _action(String tooltip, List<List<dynamic>> icon, VoidCallback? onPressed, {bool destructive = false}) => Tooltip(
    message: tooltip,
    child: CupertinoButton(
      padding: EdgeInsets.zero, minimumSize: const Size.square(AppStyle.iconTarget),
      onPressed: onPressed,
      child: HugeIcon(icon: icon, size: AppStyle.iconSize,
        color: onPressed == null ? CupertinoColors.inactiveGray : destructive ? CupertinoColors.systemRed : CupertinoColors.activeBlue),
    ),
  );

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Dialog(
      backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: CupertinoPopupSurface(child: SizedBox(
        width: 520, height: MediaQuery.sizeOf(context).height * .6,
        child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [
            Expanded(child: Text('Downloads'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
            _action('New download'.tr, HugeIcons.strokeRoundedAdd01, () {
              Navigator.of(context).pop();
              controller.openDialogDownload();
            }),
            _action('Refresh history'.tr, HugeIcons.strokeRoundedRefresh01, controller.loadDownloadHistory),
            _action('Close history'.tr, HugeIcons.strokeRoundedCancel01, () => Navigator.of(context).pop()),
          ]),
          const SizedBox(height: 12),
          Expanded(child: Obx(() => controller.history.isEmpty
              ? Center(child: Text('No download history yet.'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(AppStyle.radius + 2),
                  child: ColoredBox(color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
                    child: ListView.separated(
                      padding: EdgeInsets.zero, itemCount: controller.history.length,
                      separatorBuilder: (_, _) => Divider(height: 1, thickness: .5, indent: 12,
                        color: CupertinoColors.separator.resolveFrom(context)),
                      itemBuilder: (context, index) {
                        final activity = controller.history[index];
                        final data = controller.historyContent(activity);
                        final output = data['output_path'] as String? ?? '';
                        final name = output.isNotEmpty ? p.basename(output) : (data['filename'] as String? ?? '').isNotEmpty
                            ? data['filename'] as String : data['url'] as String? ?? 'Download'.tr;
                        final status = '${data['ev'] ?? 'unknown'}';
                        final label = switch (status) {
                          'finish' => 'Completed'.tr,
                          'cancelled' => 'Cancelled'.tr,
                          'failed' => 'Failed'.tr,
                          'start' => 'Starting'.tr,
                          _ => status.tr,
                        };
                        return CupertinoListTile(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          title: Tooltip(message: name, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColor.text))),
                          subtitle: Tooltip(message: '${data['error'] ?? data['url'] ?? ''}', child: Text(
                            '$label · ${activity.updatedAt?.replaceFirst('T', ' ') ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColor.muted))),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (output.isNotEmpty && status == 'finish')
                              _action('Reveal output'.tr, HugeIcons.strokeRoundedFolderOpen, () => controller.revealOutput(output)),
                            Obx(() {
                              controller.jobRevision.value;
                              return _action('Load settings to retry'.tr, HugeIcons.strokeRoundedArrowTurnBackward, controller.job.running ? null : () {
                                controller.restoreDownload(activity);
                                Navigator.of(context).pop();
                                controller.openDialogDownload();
                              });
                            }),
                            _action('Delete history entry'.tr, HugeIcons.strokeRoundedDelete02,
                              () => controller.deleteDownloadHistory(activity), destructive: true),
                          ]),
                        );
                      },
                    ),
                  ),
                ))),
        ])),
      )),
    );
  }
}
