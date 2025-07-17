import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'helper_toast.dart';

mixin HelperOpener {
  static Future<void> openFolder(String path) async {
    final Uri uri = Uri.file(path);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await HelperToast.error('Could not open folder');
    }
  }

  static Future<void> openFile(String path) async {
    final Uri uri = Uri.file(path);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await HelperToast.error('Could not open file');
    }
  }

  static Future<void> openFolderFromFile(String filePath) async {
    File file = File(filePath);
    if (await file.exists()) {
      String directoryPath = file.parent.path;
      Uri uri = Uri.parse('file://$directoryPath');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } else {
      print('File does not exist at path: $filePath');
    }
  }
}
