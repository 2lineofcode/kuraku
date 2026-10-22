import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../data/models/library_entity.dart';
import 'helper_misc.dart';

mixin HelperFilePicker {
  static const videoExtensions = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'];

  static bool isTemporaryDownloadPath(String path) => p.split(path).any((part) =>
    ['.downiepart', '.part', '.tmp', '.crdownload', '.download'].any(part.toLowerCase().endsWith));

  static bool isSupportedVideoPath(String path) =>
    videoExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

  static bool isSupportedImagePath(String path) =>
    ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(path.split('.').last.toLowerCase());

  static Future<List<String>> existingImages(Iterable<String> paths, {bool Function()? cancelled}) async {
    final unique = paths.toSet().toList();
    final available = <String>[];
    for (var start = 0; start < unique.length; start += 16) {
      if (cancelled?.call() ?? false) return [];
      final batch = unique.skip(start).take(16).toList();
      final exists = await Future.wait(batch.map((path) => File(path).exists()));
      for (var index = 0; index < batch.length; index++) {
        if (exists[index]) available.add(batch[index]);
      }
    }
    return available;
  }

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
    final imageFiles = <String>[];

    await for (final file in directory.list(recursive: true)) {
      if (isTemporaryDownloadPath(file.path)) continue;
      if (file is Directory) {
        subfolders.add(file.path);
        continue;
      }

      if (file is! File) continue;
      if (isSupportedImagePath(file.path)) {
        if (!file.path.split(Platform.pathSeparator).any((part) => part.startsWith('.'))) imageFiles.add(file.path);
        continue;
      }
      if (!isSupportedVideoPath(file.path)) continue;
      if (await file.length() >= 10 * 1024 * 1024) videoFiles.add(file.path);
    }

    imageFiles.sort();
    final item = Library(
      totalVideo: videoFiles.length,
      rootFolder: path,
      subFolder: subfolders,
      videos: videoFiles,
      images: imageFiles,
    );
    return item;
  }
}
