import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';

import '../core/app_logging.dart';

mixin HelperMedia {
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
      final width = properties['width'], height = properties['height'];
      if (width is num && height is num && width.isFinite && height.isFinite && width.toInt() > 0 && height.toInt() > 0) {
        return StreamInformation(properties);
      }
    }
    return null;
  }
}
