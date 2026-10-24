import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_media.dart';
import '../../../utils/helper_misc.dart';
import '../../widgets/widget_controls.dart';

class ToolsDuplicateComparison extends StatefulWidget {
  const ToolsDuplicateComparison({super.key, required this.videos, required this.onClose, this.readFile = HelperMedia.readFile});

  final List<Videos> videos;
  final VoidCallback onClose;
  final Future<MediaInformation?> Function(String) readFile;

  static Future<void> open(List<Videos> videos) async {
    late final OverPanel panel;
    panel = OverPanel(
      alignment: Alignment.center,
      width: Get.width < 932 ? Get.width - 32 : 900,
      height: Get.height * .8,
      color: AppColor.container,
      child: ToolsDuplicateComparison(videos: List.of(videos), onClose: () => Overlayment.dismiss(panel)),
    );
    await Overlayment.show(panel, context: Get.context);
  }

  @override
  State<ToolsDuplicateComparison> createState() => _ToolsDuplicateComparisonState();
}

class _ToolsDuplicateComparisonState extends State<ToolsDuplicateComparison> {
  final _information = <String, MediaInformation?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final video in widget.videos) {
      if (!mounted) return;
      final path = video.videoPath ?? '';
      MediaInformation? information;
      try { information = await widget.readFile(path); } catch (_) { /* Unavailable files retain their library metadata. */ }
      if (!mounted) return;
      setState(() => _information[path] = information);
    }
  }

  Map<String, String> _fields(Videos video) {
    final information = _information[video.videoPath ?? ''];
    final properties = information?.getAllProperties();
    final format = properties?['format'] is Map ? properties!['format'] as Map : <dynamic, dynamic>{};
    final stream = HelperMedia.videoStream(information)?.getAllProperties() ?? {};
    final rate = num.tryParse('${format['bit_rate'] ?? stream['bit_rate']}');
    final seconds = double.tryParse('${format['duration']}');
    final size = int.tryParse('${format['size']}') ?? video.filesize;
    return {
      'File': p.basename(video.videoPath ?? ''),
      'Path': video.videoPath ?? '—',
      'Resolution': stream['width'] == null || stream['height'] == null
          ? (video.quality ?? '').isEmpty ? '—' : video.quality! : '${stream['width']} × ${stream['height']}',
      'Codec': HelperMedia.codecLabel(stream['codec_name']),
      'Bitrate': rate != null && rate.isFinite && rate > 0 ? '${(rate / 1000).toStringAsFixed(0)} kb/s' : '—',
      'Duration': seconds != null && seconds.isFinite && seconds >= 0
          ? Duration(seconds: seconds.round()).toString().split('.').first
          : (video.duration ?? 0) > 0 ? HelperMisc.durationFormatDB(video.duration!) : '—',
      'File Size': size != null && size.isFinite && size > 0 ? size.toFileSizeFormat() : '—',
      'Status': !_information.containsKey(video.videoPath ?? '') ? 'Loading...'.tr
          : information == null ? 'Could not read video properties. The file may be missing, unreadable or unsupported.'.tr : 'Available'.tr,
    };
  }

  @override
  Widget build(BuildContext context) {
    final columns = widget.videos.map(_fields).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('Compare duplicates'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        if (_information.length < widget.videos.length) const CupertinoActivityIndicator(),
        const SizedBox(width: 12),
        AppButton(label: 'Close'.tr, onPressed: widget.onClose),
      ])),
      Expanded(child: SingleChildScrollView(child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 40, dataRowMaxHeight: 96,
          columns: [
            DataColumn(label: Text('Properties'.tr)),
            for (var i = 0; i < columns.length; i++) DataColumn(label: Text('#${i + 1}')),
          ],
          rows: [
            if (columns.isNotEmpty) for (final label in columns.first.keys) DataRow(cells: [
              DataCell(Text(label.tr)),
              for (final column in columns) DataCell(SizedBox(width: 230, child: Tooltip(
                message: column[label]!, child: Text(column[label]!, maxLines: 3, overflow: TextOverflow.ellipsis),
              ))),
            ]),
          ],
        ),
      ))),
    ]);
  }
}
