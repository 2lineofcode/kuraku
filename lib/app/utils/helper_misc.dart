import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../env.g.dart';
import 'helper_toast.dart';

mixin HelperMisc {

  static String __getVideoCode(String fileName) {
    final List<RegExp> expressions = [
      RegExp(r'([a-zA-Z]{2,})-([0-9]{3,})'),
    ];
    final matches = expressions.map((exp) => exp.firstMatch(fileName)).toList();
    final match = matches.firstWhere((m) => m != null, orElse: () => null);
    return match != null ? '${match.group(1)?.toUpperCase()}-${match.group(2)}' : '';
  }

  static bool __isValidVideoCode(String code) {
    if (code.trim().isEmpty) return false;

    const _blacklistedPrefixes = [
      'TK', '7', '9', 'K9', 'FTKT', 'GOOE', 'JTKT', 'GTKT', 'DDMP', 'DMPXA', 'USTD', 
      'VWBS', 'HPXR', 'VWAS', 'TCBD', 'DAXA', 'TWUSS', 'PJXF', 'KKC', 'GNXF', 'JAXA', 'UHB', 
      'BPUH', 'GNXT', 'ZTKT', 'PB', 'D1', 'D2', 'D3', 'DK',
    ];
    const _blacklistedSuffixes = [
      'BOD', 'DOD', 'Ta', 'Tb', 'Tc', 'Td', 'Te', 
      'TK', 'TK1', 'TK2', 'TK3', 'EC', '4D', '5D', 'DL',
    ];

    final hasValidFormat = RegExp(r'^[a-zA-Z]{2,}-[0-9]{3,}$').hasMatch(code);
    final hasBlacklistedPrefix = _blacklistedPrefixes.any((prefix) => code.startsWith(prefix));
    final hasBlacklistedSuffix = _blacklistedSuffixes.any((suffix) => code.endsWith(suffix));
    return hasValidFormat && !hasBlacklistedPrefix && !hasBlacklistedSuffix;
  }

  static String __getLastSegments(String path, {int n = 4}) {
    if (path.isEmpty) return '';
    List<String> segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= n) return path;
    segments = segments.sublist(segments.length - n);
    return '.../${segments.join('/')}';
  }

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
      '1920x1080': 'FHD (1080p)',
      '1280x720': 'HD (720p)',
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
}

extension HelperMiscExt on String {
  String getVideoCode() => HelperMisc.__getVideoCode(this);
  bool isValidVideoCode() => HelperMisc.__isValidVideoCode(this);
  String noExt() => replaceAll('.mp4', '').replaceAll('mp4', '');
  String getExt() => split('.').last;
  String getFileName() => split('/').last;
  String getLastPath() => split('/').last;
  String getLastSegments({int segment = 4}) => HelperMisc.__getLastSegments(this, n: segment);
  String getFilePath() => split('/').sublist(0, split('/').length - 1).join('/');
  String imgUrlFormat() => '${Env.imgUrl}/$this.jpg';
}
