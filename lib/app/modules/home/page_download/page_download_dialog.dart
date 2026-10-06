import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import 'page_download_controller.dart';

class PageDownloadDialog extends StatelessWidget {
  const PageDownloadDialog({super.key, required this.controller});
  final PageDownloadController controller;

  Widget _field(String label, TextEditingController field, {bool enabled = true, bool number = false, FocusNode? focusNode}) => Tooltip(
    message: label,
    child: Semantics(label: label, child: CupertinoTextField(
      controller: field, focusNode: focusNode, enabled: enabled, placeholder: label,
      style: TextStyle(fontSize: 12, color: AppColor.text), padding: const EdgeInsets.all(8),
      keyboardType: number ? TextInputType.number : TextInputType.text,
    )),
  );

  Widget _number(String label, TextEditingController field, bool enabled) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 10, color: AppColor.muted)),
    const SizedBox(height: 4),
    _field(label, field, enabled: enabled, number: true),
  ]));

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Dialog(
      backgroundColor: AppColor.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Padding(padding: const EdgeInsets.all(14), child: Obx(() {
          controller.jobRevision.value;
          final job = controller.job;
          final running = job.running;
          final extract = controller.mode.value == 'extract';
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Download'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'Close download dialog'.tr, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 16), onPressed: () => Navigator.of(context).pop()),
            ]),
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SizedBox(width: 110, child: DropdownButton<String>(
                  value: controller.mode.value, isExpanded: true, isDense: true,
                  dropdownColor: AppColor.panel, style: TextStyle(fontSize: 12, color: AppColor.text),
                  items: [
                    DropdownMenuItem(value: 'extract', child: Text('Website'.tr)),
                    DropdownMenuItem(value: 'auto', child: Text('Auto'.tr)),
                    DropdownMenuItem(value: 'hls', child: Text('HLS')),
                    DropdownMenuItem(value: 'file', child: Text('File'.tr)),
                    DropdownMenuItem(value: 'youtube', child: Text('YouTube')),
                  ],
                  onChanged: running ? null : (value) => controller.mode.value = value!,
                )),
                const SizedBox(width: 8),
                Expanded(child: _field('URL'.tr, controller.tecUrl, enabled: !running, focusNode: controller.fnDownloadUrl)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('Save to folder'.tr, controller.tecDirectory, enabled: !running)),
                IconButton(tooltip: 'Choose output folder'.tr, visualDensity: VisualDensity.compact, onPressed: running ? null : controller.pickDownloadDirectory, icon: const Icon(Icons.folder_open, size: 18)),
              ]),
              const SizedBox(height: 8),
              _field(extract ? 'Filename (optional · use page title)'.tr : 'Filename'.tr, controller.tecFilename, enabled: !running),
              if (extract) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Play the video in Chrome, then choose its media here.'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))),
              if (!running) Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
                tilePadding: EdgeInsets.zero, minTileHeight: 34,
                title: Text('Options'.tr, style: TextStyle(fontSize: 11)),
                children: [
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
                    CheckboxListTile(
                      dense: true, visualDensity: VisualDensity.compact, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                      title: Text('Background capture'.tr, style: TextStyle(fontSize: 11)),
                      value: controller.headless.value, onChanged: (value) => controller.headless.value = value ?? false,
                    ),
                    if (controller.headless.value) ...[
                      _field('Capture duration (seconds)'.tr, controller.tecCaptureDuration, number: true),
                      const SizedBox(height: 8),
                      _field('Play button selector (optional)'.tr, controller.tecPlaySelector),
                    ],
                    CheckboxListTile(
                      dense: true, visualDensity: VisualDensity.compact, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                      title: Text('Allow login / player popups'.tr, style: TextStyle(fontSize: 11)),
                      value: controller.allowPopups.value, onChanged: (value) => controller.allowPopups.value = value ?? false,
                    ),
                  ],
                ],
              )),
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
                    trailing: IconButton(tooltip: candidate.supported ? 'Download this media'.tr : 'Unsupported stream'.tr, icon: const Icon(Icons.download, size: 16), onPressed: job.canSelect && candidate.supported ? () async {
                      try {
                        await job.select(candidate);
                      } catch (e) {
                        controller.formError.value = '$e';
                      }
                    } : null),
                  )).toList()))),
                ],
                if (job.status == 'Completed') TextButton.icon(onPressed: () => controller.revealOutput(job.outputPath), icon: const Icon(Icons.folder_open, size: 16), label: Text(p.basename(job.outputPath), style: const TextStyle(fontSize: 11))),
              ],
              if (job.error.isNotEmpty || controller.formError.value.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText((controller.formError.value.isNotEmpty ? controller.formError.value : job.error).tr, style: const TextStyle(fontSize: 11, color: Colors.redAccent))),
              if (job.logs.isNotEmpty) ExpansionTile(
                tilePadding: EdgeInsets.zero, minTileHeight: 34,
                title: Text('Log'.tr, style: TextStyle(fontSize: 11)),
                children: [SizedBox(height: 120, width: double.infinity, child: SingleChildScrollView(reverse: true, child: SelectableText(job.logs.join('\n'), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))))],
              ),
            ]))),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () {
                Navigator.of(context).pop();
                controller.openDownloadLog();
              }, child: Text('History'.tr, style: TextStyle(fontSize: 11))),
              const Spacer(),
              if (running) TextButton(onPressed: job.cancelled ? null : controller.killProcessDownload, child: Text('Cancel download'.tr, style: TextStyle(fontSize: 12)))
              else FilledButton(onPressed: controller.startDownload, child: Text(extract ? 'Capture'.tr : 'Download'.tr, style: const TextStyle(fontSize: 12))),
            ]),
          ]);
        })),
      ),
    );
  }
}

class PageDownloadHistoryDialog extends StatelessWidget {
  const PageDownloadHistoryDialog({super.key, required this.controller});
  final PageDownloadController controller;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColor.panel, insetPadding: const EdgeInsets.all(24),
    child: SizedBox(width: 520, height: MediaQuery.sizeOf(context).height * .6, child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
      Row(children: [
        Expanded(child: Text('Downloads'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'New download'.tr, icon: const Icon(Icons.add, size: 18), onPressed: () {
          Navigator.of(context).pop();
          controller.openDialogDownload();
        }),
        IconButton(tooltip: 'Refresh history'.tr, icon: const Icon(Icons.refresh, size: 18), onPressed: controller.loadDownloadHistory),
        IconButton(tooltip: 'Close history'.tr, icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.of(context).pop()),
      ]),
      Expanded(child: Obx(() => controller.history.isEmpty
          ? Center(child: Text('No download history yet.'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)))
          : ListView.builder(itemCount: controller.history.length, itemBuilder: (context, index) {
              final activity = controller.history[index];
              final data = controller.historyContent(activity);
              final output = data['output_path'] as String? ?? '';
              final name = output.isNotEmpty ? p.basename(output) : (data['filename'] as String? ?? '').isNotEmpty ? data['filename'] as String : data['url'] as String? ?? 'Download'.tr;
              final status = '${data['ev'] ?? 'unknown'}';
              return ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                subtitle: Tooltip(message: '${data['error'] ?? data['url'] ?? ''}', child: Text('${status.tr} · ${activity.updatedAt ?? ''}', style: const TextStyle(fontSize: 10))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (output.isNotEmpty && status == 'finish') IconButton(tooltip: 'Reveal output'.tr, icon: const Icon(Icons.folder_open, size: 16), onPressed: () => controller.revealOutput(output)),
                  Obx(() {
                    controller.jobRevision.value;
                    return IconButton(tooltip: 'Load settings to retry'.tr, icon: const Icon(Icons.replay, size: 16), onPressed: controller.job.running ? null : () {
                      controller.restoreDownload(activity);
                      Navigator.of(context).pop();
                      controller.openDialogDownload();
                    });
                  }),
                  IconButton(tooltip: 'Delete history entry'.tr, icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => controller.deleteDownloadHistory(activity)),
                ]),
              );
            }))),
    ]))),
  );
}
