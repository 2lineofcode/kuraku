import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_logging.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_toast.dart';
import '../home_panel/home_panel_library.dart';
import 'page_search_tab.dart';

class SearchFileDrag extends StatelessWidget {
  const SearchFileDrag({super.key, required this.controller, required this.video, required this.child});

  final PageSearchTab controller;
  final Videos video;
  final Widget child;
  static const channel = MethodChannel('javit/file_drag');

  bool get canDrag => !controller.isClosed && controller.selectedVideos.contains(video);

  Future<void> startDrag() async {
    if (!canDrag || !HomePanelLibrary.canStartFileDrag) return;
    HomePanelLibrary.fileDragInProgress = true;
    final selected = controller.videos.where(controller.selectedVideos.contains).toList();
    final files = <String, Videos>{};
    try {
      for (final item in selected) {
        final path = item.videoPath ?? '';
        if (!p.isAbsolute(path) || !await File(path).exists()) {
          throw FileSystemException('File is unavailable', path);
        }
        files[path] = item;
      }
      final bookmarks = await channel.invokeMapMethod<String, dynamic>('bookmark', files.keys.toList());
      if (bookmarks == null || bookmarks.length != files.length) throw StateError('Could not track the selected files');
      if (!canDrag) return;
      final operation = await channel.invokeMethod<String>('drag', files.keys.toList());
      if (operation != 'move' && operation != 'copy') return;
      // ponytail: wait up to 10s for Finder; longer transfers need a library rescan.
      for (var attempt = 0; operation == 'move' && attempt < 20; attempt++) {
        if (!files.keys.any((path) => File(path).existsSync())) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final resolved = await channel.invokeMapMethod<String, String>('resolve', bookmarks) ?? {};
      final moves = <String, String>{};
      final missing = <String>[];
      for (final oldPath in files.keys) {
        if (await File(oldPath).exists()) continue;
        final newPath = resolved[oldPath];
        if (newPath != null && newPath != oldPath && await File(newPath).exists()) {
          moves[oldPath] = newPath;
        } else {
          missing.add(oldPath);
        }
      }
      await controller.applyFileMoves(files, moves, missing);
      if (missing.isNotEmpty || operation == 'move' && files.keys.any((path) => File(path).existsSync())) {
        await HelperToast.warn('Some moved paths could not be confirmed. Add the destination folder to your library and rescan after Finder finishes.');
      }
    } catch (e) {
      AppLog.logE('File drag failed: $e');
      await HelperToast.error('File drag failed: $e');
    } finally {
      HomePanelLibrary.fileDragInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    return Obx(() => GestureDetector(
      onPanStart: canDrag ? (_) => startDrag() : null,
      child: child,
    ));
  }
}
