import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../env.g.dart';
import '../core/const.dart';
import 'helper_toast.dart';

mixin HelperMisc {

  static String durationFormatDB(num durationInMinutes) {
    if (durationInMinutes < 0) {
      return 'Invalid duration';
    }

    final hours = durationInMinutes ~/ 60;
    final minutes = durationInMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours hours, $minutes minutes';
    } else if (hours > 0) {
      return '$hours hours';
    } else if (minutes > 0) {
      return '$minutes minutes';
    } else {
      return '0 minutes';
    }
  }

  static String durationFormatFFmpeg(num totalSeconds) {
    if (totalSeconds.isNaN || totalSeconds.isInfinite) {
      return 'Invalid Duration';
    }
    if (totalSeconds < 0) return 'Invalid Duration (Negative)';

    int milliseconds = (totalSeconds * 1000).round();
    int hours = (milliseconds ~/ 3600000);
    milliseconds %= 3600000;
    int minutes = (milliseconds ~/ 60000);
    milliseconds %= 60000;
    int seconds = (milliseconds ~/ 1000);
    int remainingMilliseconds = milliseconds % 1000;
    List<String> parts = [];
    if (hours > 0) parts.add('$hours hour');
    if (minutes > 0) parts.add('$minutes minutes');

    if (remainingMilliseconds > 0 || (hours == 0 && minutes == 0 && seconds == 0 && totalSeconds > 0)) {
      if (remainingMilliseconds > 0) {
        //
      } else if (totalSeconds == 0) {
        return '0 second';
      }
    }

    if (parts.isEmpty) return '0 second';

    return parts.join(', ');
  }

  static void copyToClipboard(
    String? text, {
    bool? showToast = false,
    String? toastMessage,
    Duration? toastDuration,
    Alignment? alignment,
  }) {
    if (text == null) return;

    final data = ClipboardData(text: text);
    Clipboard.setData(data);

    if (showToast == true) {
      toastMessage ??= '[$text] Copied to clipboard';
      HelperToast.info(toastMessage, duration: toastDuration ?? 2.seconds, alignment: alignment);
    }
  }

  static String formatActressName(String name) {
    String cleanAndFormatPart(String part) {
      String cleanedPart = part.replaceAll(RegExp(r'\d+'), '');
      if (cleanedPart.isEmpty) return '';
      return cleanedPart[0].toUpperCase() + cleanedPart.substring(1).toLowerCase();
    }

    if (name.contains('_') || name.contains('.')) {
      String namePart = name.split('.')[0];
      List<String> parts = namePart.split('_');

      List<String> formattedParts = parts.map((part) {
        return cleanAndFormatPart(part);
      }).toList();

      return formattedParts.reversed.join(' ');
    } else {
      List<String> parts = name.split(' ');

      List<String> formattedParts = parts.map((part) {
        return cleanAndFormatPart(part);
      }).toList();

      return formattedParts.join(' ');
    }
  }

  static String formatVideoQuality(String quality) {
    if (quality.isEmptyOrNull) return '';

    const Map<String, String> videoQualities = {
      '3840x2160': '4K',
      '2560x1440': '2K (QHD)',
      '2048x1080': '2K (DCI)',
      '2224x1080': 'FHD+ (20:9)',
      '1920x1080': 'FHD (1080p)',
      '1920x816': 'FHD (Cinematic)', // Cinema standard 2.35:1
      '1920x800': 'FHD (Ultrawide)', // Cinema standard 21:9
      '1918x1036': 'FHD (Custom)',
      '1912x1088': 'FHD (Custom)',
      '1080x1920': 'FHD (Portrait)',
      '1280x720': 'HD (720p)',
      '720x1600': 'HD+ (20:9)',
      '720x1480': 'HD+ (18.5:9)',
      '720x1280': 'HD (Portrait)',
      '720x1278': 'HD (Custom)',
      '628x1080': 'FHD (Portrait)',
      '608x1080': 'FHD (Portrait)',
      '606x1080': 'FHD (Portrait)',
      '544x960': 'qHD (960p)',
      '540x960': 'qHD (960p)',
      '488x1080': 'FHD (Portrait)',
      '486x1080': 'FHD (Portrait)',
      '405x720': 'HD (Portrait)',
      '404x720': 'HD (Portrait)',
      '360x640': 'nHD (360p)',
      '854x480': 'SD (480p)',
    };

    final knownQuality = videoQualities[quality];
    if (knownQuality != null) {
      return knownQuality;
    }

    final parts = quality.split('x');
    final height = int.tryParse(parts[1]);
    if (height! >= 1080)  return 'FHD (Potrait)';
    else if (height >= 720) return 'HD (Potrait)';
    else if (height >= 480) return 'SD (Potrait)';
    else if (height >= 360) return '360p (Potrait)';
    else if (height >= 240) return '240p (Potrait)';
    else if (height >= 144) return '144p (Potrait)';
    return 'Unknown';
  }

  static String timeAgo(String format, String datetime) {
    try {
      final date = datetime.toDateEx(format: format);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'Today';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays > 1 && diff.inDays <= 7) {
        return '${diff.inDays} days ago';
      } else {
        return date.toStringEx(format: kMdY);
      }
    } catch (e) {
      return 'Invalid Date';
    }
  }

  static bool isExternalDrive(String? filePath) {
    if (filePath == null) return false;
    final path = Platform.isWindows ? filePath.toUpperCase() : filePath;

    if (Platform.isWindows) {
      if (path.length > 2 && path[1] == ':') {
        final driveLetter = path[0];
        return driveLetter.compareTo('E') > 0;
      }
      return false;
    } else if (Platform.isMacOS) {
      return path.startsWith('/Volumes/');
    } else if (Platform.isLinux) {
      return path.startsWith('/media/') || path.startsWith('/mnt/');
    }
    return false;
  }

  static Future<void> playSoundDownloadComplate() async {
    final player = AudioPlayer();
    await player.play(AssetSource('notif.mp3'));
  }

}

// ────────────────────────────────────────────────────────────────
// ⵌ private class
// ────────────────────────────────────────────────────────────────
mixin _JavitExtension {
  static String __getVideoCode(String fileName) {
    final List<RegExp> expressions = [
      RegExp(r'([A-Za-z]{2,})-([0-9]{2,})(?:-[A-Za-z0-9]+)?'),
    ];
    final matches = expressions.map((exp) => exp.firstMatch(fileName)).toList();
    final match = matches.firstWhere((m) => m != null, orElse: () => null);
    return match != null ? '${match.group(1)?.toUpperCase()}-${match.group(2)}' : '';
  }

  static bool __isValidVideoCode(String code) {
    if (code.trim().isEmpty) return false;

    final match = RegExp(r'^([A-Za-z]{2,})-([0-9]{2,})(?:-[A-Za-z0-9]+)?$').firstMatch(code);
    if (match == null) return false;

    final number = match.group(2)!;
    if (number.length > 5) return false;

    return true;
  }

  static String __getLastSegments(String path, {int n = 4}) {
    if (path.isEmpty) return '';
    List<String> segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= n) return path;
    segments = segments.sublist(segments.length - n);
    return '.../${segments.join('/')}';
  }

  static bool __isHasEnSub(String filepath) {
    final filename = filepath.toLowerCase();
    if (filename.getVideoCode() == '') return false;

    final detect = ['-en', '-sub'];
    for (final d in detect) if (filename.contains(d)) return true;
    return false;
  }

  static bool __isHasIdSub(String filepath) {
    final filename = filepath.toLowerCase();
    if (filename.getVideoCode() == '') return false;

    final detect = ['-id', 'indo'];
    for (final d in detect) if (filename.contains(d)) return true;
    return false;
  }

  static bool __isHasUncensored(String filepath) {
    final filename = filepath.toLowerCase();
    if (filename.getVideoCode() == '') return false;

    final detect = ['-un', '-rm', 'reducing mosaic'];
    for (final d in detect) if (filename.contains(d)) return true;
    return false;
  }
}


extension JavitExtString on String {
  String getVideoCode() => _JavitExtension.__getVideoCode(this);
  bool isValidVideoCode() => _JavitExtension.__isValidVideoCode(this);
  String noExt() => replaceAll('.mp4', '').replaceAll('mp4', '');
  String getExt() => split('.').last;
  String getFileName() => split('/').last.split('\\').last;
  String getLastPath() => split('/').last.split('\\').last;
  String getLastSegments({int segment = 4}) => _JavitExtension.__getLastSegments(this, n: segment);
  String getFilePath() => split('/').sublist(0, split('/').length - 1).join('/');

  // ---
  String genImageUrl() {
    if (startsWith('http')) return this;

    var output = this;
    if (endsWith('ps')) output = replaceFirst('ps', 'pl');
    return '${Env.imgUrl}/$output.jpg';
  }

  String genAvatarUrl() {
    if (startsWith('http')) return this;
    return '${Env.actressUrl}/$this';
  }

  String genTrailerUrl() => '${Env.vidUrl}$this';

  // ---
  bool isHasEnSub() => _JavitExtension.__isHasEnSub(this);
  bool isHasIdSub() => _JavitExtension.__isHasIdSub(this);
  bool isHasUncensored() => _JavitExtension.__isHasUncensored(this);
}

extension JavitExtDateTime on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}

extension JavitExtNumber on num {
  String numberFormat() => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(this);
}
