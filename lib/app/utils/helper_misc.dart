import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../env.g.dart';
import '../core/app_logging.dart';
import 'helper_toast.dart';

mixin HelperMisc {
  static String getLastPath(String path) => path.split('/').last;

  static String getLastSegments(String path, {int n = 4}) {
    if (path.isEmpty) return '';
    List<String> segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= n) return path;
    segments = segments.sublist(segments.length - n);
    return '.../${segments.join('/')}';
  }

  static String getVideoCode(String fileName) {
    final List<RegExp> expressions = [
      RegExp(r'([a-zA-Z]{2,})-([0-9]{3,})'),
    ];
    final matches = expressions.map((exp) => exp.firstMatch(fileName)).toList();
    final match = matches.firstWhere((m) => m != null, orElse: () => null);
    return match != null ? '${match.group(1)?.toUpperCase()}-${match.group(2)}' : '';
  }

  static bool isValidVideoCode(String code) {
    return RegExp(r'^[a-zA-Z]{2,}-[0-9]{3,}$').hasMatch(code);
  }

  static String durationFormat0(num durationInMinutes) {
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

  static String durationFormat1(num milliseconds) {
    int totalSeconds = (milliseconds / 1000).truncate();
    int hours = (totalSeconds / 3600).truncate();
    int minutes = ((totalSeconds % 3600) / 60).truncate();
    List<String> parts = [];
    if (hours > 0) parts.add('$hours hour');
    if (minutes > 0) parts.add('$minutes minutes');
    if (parts.isEmpty) return '0 detik';
    return parts.join(', ');
  }

  static String durationFormat2(num totalSeconds) {
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
        return '0 detik';
      }
    }

    if (parts.isEmpty) return '0 detik';

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

  static Future<String?> decensor(String? s) async {
    if (s == null) return null;
    String resultString = s;

    try {
      String fileContent = await rootBundle.loadString('assets/decensor.csv');
      List<String> lines = fileContent.split('\n');

      for (String line in lines) {
        String trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;

        List<String> rowDecensor = trimmedLine.split(',');
        if (rowDecensor.length == 2) {
          resultString = resultString.replaceAll(rowDecensor[0], rowDecensor[1]);
        }
      }
    } catch (e) {
      AppLog.logE('Error reading decensor.csv from assets: $e');
    }

    return resultString;
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

  static String decodeHtml(String htmlString) {
    String decodedString = htmlString.replaceAll('&quot;', '"');
    decodedString = decodedString.replaceAll('&amp;', '&');
    return decodedString;
  }
}

extension HelperMiscExt on String {
  String noExt() => replaceAll('.mp4', '').replaceAll('mp4', '');
  String getExt() => split('.').last;
  String getFileName() => split('/').last;
  String getVideoCode() => HelperMisc.getVideoCode(this);
  String getLastPath() => split('/').last;
  String getLastSegments({int segment = 4}) => HelperMisc.getLastSegments(this, n: segment);
  String removeExt() => split('.').sublist(0, split('.').length - 1).join('.');
  String removePath() => split('/').sublist(0, split('/').length - 1).join('/');
  String removeFileName() => split('/').sublist(0, split('/').length - 1).join('/');
  String removeFileExt() => split('.').sublist(0, split('.').length - 1).join('.');
  String removeFileExt2() => split('.').sublist(0, split('.').length - 2).join('.');
  String imgUrl() => '${Env.imgUrl}/$this.jpg';
}
