import 'package:ex_kit/ex.dart';

mixin HelperMisc {
  static String generateID() => ExRandom.alphaNumeric(12);

  static String getLastPath(String path) => path.split('/').last;

  static String getLastSegments(String path, {segment = 3}) {
    List<String> segments = path.split('/');
    if (segments.length > segment) {
      segments = segments.sublist(segments.length - 3);
    }
    return '.../${segments.join('/')}';
  }

  static String getVideoCode(String fileName) {
    final List<RegExp> expressions = [
      // RegExp(r'([a-z]{2,})-([0-9]{3})'),
      // RegExp(r'([A-Z]{2,})-([0-9]{3})'),
      // RegExp(r'([A-Z]{2,})([0-9]{3})'),
      RegExp(r'([a-zA-Z]{2,})-([0-9]{3,})'),
    ];
    final matches = expressions.map((exp) => exp.firstMatch(fileName)).toList();
    final match = matches.firstWhere((m) => m != null, orElse: () => null);

    //// ! test
    // final x1 = HelperMisc.getVideoCode('HND-449-SUB [English Subtitle] When I Awoke I Found That I Had Been Creampie Fucked... Aki Sasaki.mp4');
    // final x2 = HelperMisc.getVideoCode('FC2PPV-4524307 Immediately after giving birth her breasts  time from her bare thighs.mp4');
    // final x3 = HelperMisc.getVideoCode('DANDY-634 Is It Really Good For Me For The First Time Natural Actress Yoshikawa Ai Noumi s Help With Gratitude.mp4');
    // final x4 = HelperMisc.getVideoCode('10-022324-01 Creampie all over Momo s freshly shaved sensitive pussy.mp4');
    // final x5 = HelperMisc.getVideoCode('Suki Sin - Slutty MILF Swallows A Huge Load - PervMom.mp4');
    // final x6 = HelperMisc.getVideoCode('PPPE-236-RM [Reducing Mosaic] Spence Breast Development Clinic Itsukaichi Mei.mp4');
    // final x7 = HelperMisc.getVideoCode('YMDD-406-RM [Reducing Mosaic] Little Sister  Himari Kosaka.mp4');
    // final x8 = HelperMisc.getVideoCode('HEYZO-1048 | Pekerja Kantor Cantik Nakal - Yui Hatano');
    // final x9 = HelperMisc.getVideoCode('Queencla Colmek Dua Jari Memek Gemoy ID 74509541 HOT-15');
    // print('x1: $x1');
    // print('x2: $x2');
    // print('x3: $x3');
    // print('x4: $x4');
    // print('x5: $x5');
    // print('x6: $x6');
    // print('x7: $x7');
    // print('x8: $x8');
    // print('x9: $x9');

    return match != null ? '${match.group(1)?.toUpperCase()}-${match.group(2)}' : '';
  }

  static isValidVideoCode(String code) {
    return RegExp(r'^[a-zA-Z]{2,}-[0-9]{3,}$').hasMatch(code);
  }

  static String durationFormat(num durationInMinutes) {
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
}

extension HelperMiscExt on String {
  String noExt() => replaceAll('.mp4', '').replaceAll('mp4', '');
  String getExt() => split('.').last;
  String getFileName() => split('/').last;
  String getVideoCode() => HelperMisc.getVideoCode(this);
  String getLastPath() => split('/').last;
  String getLastSegments({segment = 3}) => HelperMisc.getLastSegments(this, segment: segment);
  String removeExt() => split('.').sublist(0, split('.').length - 1).join('.');
  String removePath() => split('/').sublist(0, split('/').length - 1).join('/');
  String removeFileName() => split('/').sublist(0, split('/').length - 1).join('/');
  String removeFileExt() => split('.').sublist(0, split('.').length - 1).join('.');
  String removeFileExt2() => split('.').sublist(0, split('.').length - 2).join('.');
}
