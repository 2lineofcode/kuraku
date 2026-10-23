import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;

import '../../core/app_color.dart';
import '../../utils/helper_media.dart';
import '../../utils/helper_misc.dart';
import 'widget_style.dart';

class VideoPropertiesDialog extends StatefulWidget {
  const VideoPropertiesDialog({super.key, required this.path, this.information, required this.onClose});

  final String path;
  final Future<MediaInformation?>? information;
  final VoidCallback onClose;

  static Future<void> open(String path, {Future<MediaInformation?>? information}) async {
    late final OverPanel dialog;
    dialog = OverPanel(
      alignment: Alignment.center,
      width: Get.width < 552 ? Get.width - 32 : 520,
      height: Get.height * .8,
      color: AppColor.container,
      backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
      animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
      child: VideoPropertiesDialog(path: path, information: information,
        onClose: () => Overlayment.dismiss(dialog)),
    );
    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(dialog, context: Get.context);
  }

  @override
  State<VideoPropertiesDialog> createState() => _VideoPropertiesDialogState();
}

class _VideoPropertiesDialogState extends State<VideoPropertiesDialog> {
  late final _information = widget.information ?? HelperMedia.readFile(widget.path);

  String _value(dynamic value) => value == null || '$value'.trim().isEmpty || value == 'N/A' ? '—' : '$value';

  String _bitrate(dynamic value) {
    final rate = num.tryParse('$value');
    return rate != null && rate.isFinite && rate > 0 ? '${(rate / 1000).toStringAsFixed(0)} kb/s' : '—';
  }

  Widget _section(String title, Map<String, String> fields) => CupertinoFormSection.insetGrouped(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
    backgroundColor: Colors.transparent,
    decoration: BoxDecoration(color: AppColor.panel, borderRadius: BorderRadius.circular(10)),
    header: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppColor.muted)),
    children: [
      for (final field in fields.entries) CupertinoFormRow(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefix: SizedBox(width: 112, child: Text(field.key.tr, style: TextStyle(color: AppColor.text, fontSize: 12))),
        child: Align(alignment: Alignment.centerLeft,
          child: SelectableText(field.value, textAlign: TextAlign.left, style: TextStyle(color: AppColor.text, fontSize: 12))),
      ),
    ],
  );

  Widget _properties(MediaInformation information) {
    final properties = information.getAllProperties() ?? {};
    final format = properties['format'] is Map ? properties['format'] as Map : <dynamic, dynamic>{};
    final streams = properties['streams'];
    final size = int.tryParse('${format['size']}');
    final seconds = double.tryParse('${format['duration']}');
    final duration = seconds != null && seconds.isFinite && seconds >= 0 ? Duration(milliseconds: (seconds * 1000).round()) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('File'.tr, {
        'Name': p.basename(widget.path),
        'Path': widget.path,
        'Format': _value(format['format_long_name'] ?? format['format_name']),
        'File Size': size != null && size >= 0 ? size.toFileSizeFormat() : '—',
        'Duration': duration == null ? '—' : duration.toString().split('.').first,
        'Bitrate': _bitrate(format['bit_rate']),
      }),
      if (streams is List) for (final stream in streams.whereType<Map>()) ...[
        if (['video', 'audio', 'subtitle'].contains(stream['codec_type']))
          _section('${_value(stream['codec_type']).capitalizeFirst} #${_value(stream['index'])}', {
            'Codec': HelperMedia.codecLabel(stream['codec_name']),
            'Profile': _value(stream['profile']),
            if (stream['codec_type'] == 'video') ...{
              'Resolution': stream['width'] == null || stream['height'] == null ? '—' : '${stream['width']} × ${stream['height']}',
              'Frame rate': HelperMedia.frameRate(stream['avg_frame_rate'] == '0/0' ? stream['r_frame_rate'] : stream['avg_frame_rate']),
              'Pixel format': _value(stream['pix_fmt']),
              'Bit depth': _value(stream['bits_per_raw_sample']),
              'Color space': _value(stream['color_space']),
              'Color transfer': _value(stream['color_transfer']),
            },
            if (stream['codec_type'] == 'audio') ...{
              'Channels': _value(stream['channel_layout'] ?? stream['channels']),
              'Sample rate': stream['sample_rate'] == null ? '—' : '${stream['sample_rate']} Hz',
            },
            'Bitrate': _bitrate(stream['bit_rate']),
            'Language': _value(stream['tags'] is Map ? stream['tags']['language'] : null),
            'Title': _value(stream['tags'] is Map ? stream['tags']['title'] : null),
          }),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 10, 8, 10), child: Row(children: [
      Expanded(child: Text('Properties'.tr,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColor.text))),
      Tooltip(message: 'Close'.tr, child: CupertinoButton(
        padding: EdgeInsets.zero, minimumSize: const Size.square(AppStyle.iconTarget),
        onPressed: widget.onClose,
        child: const Icon(CupertinoIcons.xmark, size: AppStyle.iconSize, color: CupertinoColors.activeBlue),
      )),
    ])),
    Divider(height: 1, thickness: .5, color: AppColor.border),
    Expanded(child: SingleChildScrollView(child: FutureBuilder<MediaInformation?>(
      future: _information,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CupertinoActivityIndicator()));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Padding(padding: const EdgeInsets.all(16),
            child: Text('Could not read video properties. The file may be missing, unreadable or unsupported.'.tr));
        }
        return _properties(snapshot.data!);
      },
    ))),
    Divider(height: 1, thickness: .5, color: AppColor.border),
    Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 20), minimumSize: const Size(0, 32),
        onPressed: widget.onClose, child: Text('Close'.tr, style: const TextStyle(fontSize: 12)),
      ),
    )),
  ]);
}
