import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import '../../core/app_color.dart';
import '../../utils/helper_misc.dart';

class ExThumbnailC extends GetxController {
  final Map<String, Uint8List> _thumbnailCache = {};

  Future<String> _getThumbnailDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final thumbDir = p.join(directory.path, 'video_thumbnails');
    await Directory(thumbDir).create(recursive: true);
    return thumbDir;
  }

  String _getThumbnailFileName(String videoPath) {
    return '${p.basenameWithoutExtension(videoPath)}.jpg';
  }

  Future<Uint8List?> getThumbnail(String videopath) async {
    if (_thumbnailCache.containsKey(videopath)) return _thumbnailCache[videopath];

    final thumbDir = await _getThumbnailDirectory();
    final thumbFileName = _getThumbnailFileName(videopath);
    final thumbFilePath = p.join(thumbDir, thumbFileName);
    final thumbFile = File(thumbFilePath);

    if (await thumbFile.exists()) {
      try {
        final uint8list = await thumbFile.readAsBytes();
        _thumbnailCache[videopath] = uint8list;
        return uint8list;
      } catch (_) {
        // Fallback to generate if reading from disk fails
      }
    }

    try {
      final uint8list = await VideoCompress.getByteThumbnail(videopath, quality: 5, position: 10);

      if (uint8list != null) {
        _thumbnailCache[videopath] = uint8list;
        try {
          await thumbFile.writeAsBytes(uint8list);
        } catch (_) {
          // Ignore if saving to disk fails
        }
      }
      return uint8list;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDiskThumbnailCache() async {
    _thumbnailCache.clear();
    final thumbDir = await _getThumbnailDirectory();
    final directory = Directory(thumbDir);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class ExThumbnailV extends GetView<ExThumbnailC> {
  const ExThumbnailV({
    super.key,
    required this.imageUrl,
    required this.videoPath,
    required this.width,
    required this.height,
    this.iconSize = 64,
    this.fitMemory = BoxFit.cover,
    this.fitUrl = BoxFit.fitHeight,
  });

  final String? imageUrl;
  final String? videoPath;
  final double width;
  final double height;
  final double? iconSize;
  final BoxFit? fitMemory;
  final BoxFit? fitUrl;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ExThumbnailC());

    if (imageUrl == null || imageUrl == '') {
      return FutureBuilder<Uint8List?>(
        future: controller.getThumbnail(videoPath ?? ''),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Icon(
              CupertinoIcons.photo,
              size: iconSize,
            ).wh(width, height).centered().color(AppColor.selected);
          }

          return snapshot.hasData && snapshot.data != null
              ? Image.memory(
                  snapshot.data!,
                  fit: fitMemory,
                  width: width,
                  height: height,
                )
              : 0.heightBox;
        },
      );
    } else {
      return CachedNetworkImage(
        imageUrl: '${imageUrl?.imgUrl()}',
        fit: fitUrl,
        width: width,
        height: height,
      );
    }
  }
}
