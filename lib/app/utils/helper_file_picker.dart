import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/v4.dart';

import '../data/models/library_entity.dart';
import 'helper_misc.dart';

mixin HelperFilePicker {
  static Future<Library?> pickFolderSubFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final directory = Directory(selectedDirectory);

      List<FileSystemEntity> files = directory.listSync(recursive: true);

      // Filter semua subfolder
      List<Directory> subfolders = files
          .where((file) {
            if (file is Directory) return true;
            return false;
          })
          .map((e) => e as Directory)
          .toList();

      // Filter video files
      final videoFiles = files.where((file) {
        if (file is File) {
          // filter minimum filesize > 10MB
          if (file.lengthSync() < 10 * 1024 * 1024) return false;
          String extension = file.path.split('.').last.toLowerCase();
          return ['mp4', 'mkv', 'avi', 'mov'].contains(extension);
        }
        return false;
      }).toList();

      final item = Library(
        id: UuidV4().generate(),
        totalVideo: videoFiles.length,
        alias: HelperMisc.getLastPath(selectedDirectory),
        rootFolder: selectedDirectory,
        subFolder: subfolders.map((e) => e.path).toList(),
        videos: videoFiles.map((e) => e.path).toList(),
      );

      return item;
    }

    return null;
  }

  static Future<Library?> scanFolderAndSubFolder(String path) async {
    final directory = Directory(path);
    List<FileSystemEntity> files = directory.listSync(recursive: true);

    // Filter semua subfolder
    List<Directory> subfolders = files
        .where((file) {
          if (file is Directory) return true;
          return false;
        })
        .map((e) => e as Directory)
        .toList();

    // Filter video files
    List<FileSystemEntity> videoFiles = files.where((file) {
      if (file is File) {
        if (file.lengthSync() < 10 * 1024 * 1024) return false;
        String extension = file.path.split('.').last.toLowerCase();
        return ['mp4', 'mkv', 'avi', 'mov'].contains(extension);
      }
      return false;
    }).toList();

    final item = Library(
      id: UuidV4().generate(),
      totalVideo: videoFiles.length,
      rootFolder: path,
      subFolder: subfolders.map((e) => e.path).toList(),
      videos: videoFiles.map((e) => e.path).toList(),
    );
    return item;
  }
}
