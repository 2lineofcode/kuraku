import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';

import '../core/app_logging.dart';

mixin HelperMedia {
  static Future<MediaInformation?> readFile(String path) async {
    if (path.isEmpty || !await File(path).exists()) throw const FileSystemException('File not found');
    final session = await FFprobeKit.getMediaInformation(path);
    final information = await readInformation(session);
    if (information?.getAllProperties()?.isNotEmpty != true) throw const FormatException('Could not read video properties');
    return information;
  }

  static String codecLabel(String? codec) => switch (codec?.toLowerCase()) {
    'h264' => 'H.264',
    'hevc' || 'h265' => 'H.265',
    null || '' => '—',
    _ => codec!.toUpperCase(),
  };

  static String frameRate(dynamic value) {
    final parts = '$value'.split('/');
    final numerator = double.tryParse(parts.first);
    final denominator = parts.length == 2 ? double.tryParse(parts.last) : 1.0;
    if (numerator == null || denominator == null || denominator <= 0) return '—';
    final rate = numerator / denominator;
    return rate.isFinite && rate > 0 ? '${rate.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} fps' : '—';
  }

  static Future<MediaInformation?> readInformation(MediaInformationSession session) async {
    if (!Platform.isLinux) return session.getMediaInformation();
    try {
      // FFmpegKit's Linux serializer returns null stream objects; its raw FFprobe JSON is intact.
      final properties = jsonDecode(await session.getAllLogsAsString() ?? '');
      return properties is Map ? MediaInformation(properties) : null;
    } catch (e) {
      AppLog.logW('Could not read FFprobe metadata: $e');
      return null;
    }
  }

  static StreamInformation? videoStream(MediaInformation? information) {
    final streams = information?.getAllProperties()?['streams'];
    if (streams is! List) return null;
    for (final properties in streams.whereType<Map>()) {
      if (properties['codec_type'] != null && properties['codec_type'] != 'video') continue;
      final disposition = properties['disposition'];
      if (disposition is Map && disposition['attached_pic'] == 1) continue;
      final width = properties['width'], height = properties['height'];
      if (width is num && height is num && width.isFinite && height.isFinite && width.toInt() > 0 && height.toInt() > 0) {
        return StreamInformation(properties);
      }
    }
    return null;
  }
}
