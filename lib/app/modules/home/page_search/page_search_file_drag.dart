import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_toast.dart';
import '../home_panel/home_panel_library.dart';
import '../local_video_selection.dart';

class SearchFileDrag extends StatelessWidget {
  const SearchFileDrag({super.key, required this.controller, required this.video, required this.child});

  final LocalVideoSelection controller;
  final Videos video;
  final Widget child;
  static const channel = MethodChannel('kuraku/file_drag');

  bool get canDrag => !controller.isClosed && controller.isSelected(video);

  Future<void> startDrag() async {
    if (!canDrag || !HomePanelLibrary.canStartFileDrag) return;
    HomePanelLibrary.fileDragInProgress = true;
    final selected = controller.selectedInOrder;
    final files = <String, Videos>{};
    try {
      for (final item in selected) {
        final path = item.videoPath ?? '';
        if (!p.isAbsolute(path) || !await File(path).exists()) {
          throw FileSystemException('File is unavailable'.tr, path);
        }
        files[path] = item;
      }
      final bookmarks = await channel.invokeMapMethod<String, dynamic>('bookmark', files.keys.toList());
      if (bookmarks == null || bookmarks.length != files.length) throw StateError('Could not track the selected files'.tr);
      if (!canDrag) return;
      final operation = await channel.invokeMethod<String>('drag', files.keys.toList());
      if (operation != 'move' && operation != 'copy') return;
      // shortcut: wait up to 10s for file managers; longer transfers need a library rescan.
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
      // Linux cannot resolve a copy-and-delete move across filesystems.
      await controller.applyFileMoves(files, moves, Platform.isLinux ? [] : missing);
      if (missing.isNotEmpty || operation == 'move' && files.keys.any((path) => File(path).existsSync())) {
        await HelperToast.warn('Some moved paths could not be confirmed. Add the destination folder to your library and rescan after the file manager finishes.'.tr);
      }
    } catch (e) {
      AppLog.logE('File drag failed: $e');
      await HelperToast.error('File drag failed: @{e}'.trNamed({'e': '$e'}));
    } finally {
      if (Platform.isLinux) {
        try { await channel.invokeMethod<void>('release'); }
        catch (e) { AppLog.logW('Could not release file drag tracking: $e'); }
      }
      HomePanelLibrary.fileDragInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (![TargetPlatform.macOS, TargetPlatform.linux].contains(defaultTargetPlatform)) return child;
    return Obx(() => GestureDetector(
      onPanStart: canDrag ? (_) => startDrag() : null,
      child: child,
    ));
  }
}
