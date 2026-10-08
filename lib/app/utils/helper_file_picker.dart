import 'dart:io';

import 'package:file_picker/file_picker.dart';
import '../data/models/library_entity.dart';
import 'helper_misc.dart';

mixin HelperFilePicker {

  static bool isSupportedVideoPath(String path) =>
    ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'].contains(path.split('.').last.toLowerCase());

  // ** pickFolderSubFolder
  static Future<Library?> pickFolderSubFolder() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();

    if (selectedDirectory != null) {
      final item = await scanFolderAndSubFolder(selectedDirectory);
      item?.alias = selectedDirectory.getLastPath();
      return item;
    }

    return null;
  }

  // ** scanFolderAndSubFolder
  static Future<Library?> scanFolderAndSubFolder(String path) async {
    final directory = Directory(path);
    final subfolders = <String>[];
    final videoFiles = <String>[];

    await for (final file in directory.list(recursive: true)) {
      if (file is Directory) {
        subfolders.add(file.path);
        continue;
      }

      if (file is! File || await file.length() < 10 * 1024 * 1024) continue;
      if (isSupportedVideoPath(file.path)) videoFiles.add(file.path);
    }

    final item = Library(
      totalVideo: videoFiles.length,
      rootFolder: path,
      subFolder: subfolders,
      videos: videoFiles,
    );
    return item;
  }
}
