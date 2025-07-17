import 'package:url_launcher/url_launcher.dart';

mixin HelperOpener {
  static Future<void> openFolder(String path) async {
    final Uri uri = Uri.file(path);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not open Finder at path: $path';
    }
  }
}
