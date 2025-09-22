import 'dart:io';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:video_compress/video_compress.dart';

import '../../core/app_color.dart';
import '../../core/app_setting.dart';
import '../../utils/helper_misc.dart';

class _ExThumbnailC extends GetxController {
  final Map<String, Uint8List> _thumbnailCache = {};

  Future<String> _getThumbnailDirectory() async {
    final appPath = Get.find<AppSettingService>().appPath;
    final thumbDir = p.join(appPath, 'vid_thumbnail');
    await Directory(thumbDir).create(recursive: true);
    return thumbDir;
  }

  String _getThumbnailFileName(String videoPath) {
    return '${p.basenameWithoutExtension(videoPath)}.jpg';
  }

  Future<Uint8List?> getThumbnail(String videopath, {int? position}) async {

    if (_thumbnailCache.containsKey(videopath) && position == null) {
      return _thumbnailCache[videopath];
    }

    final thumbDir = await _getThumbnailDirectory();
    final thumbFileName = _getThumbnailFileName(videopath);
    final thumbFilePath = p.join(thumbDir, thumbFileName);
    final thumbFile = File(thumbFilePath);

    if (await thumbFile.exists() && position == null) {
      try {
        final uint8list = await thumbFile.readAsBytes();
        _thumbnailCache[videopath] = uint8list;
        return uint8list;
      } catch (_) {
        // Fallback to generate if reading from disk fails
      }
    }

    try {
      final uint8list = await VideoCompress.getByteThumbnail(videopath, quality: 5, position: position ?? 10);

      if (uint8list != null && position == null) {
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

class ExThumbnail extends GetView<_ExThumbnailC> {
  
  final String? imageUrl;
  final String? videoPath;
  final double width;
  final double height;
  final double? iconSize;
  final BoxFit? fitMemory;
  final BoxFit? fitUrl;
  final bool? withProxy;
  final double? prefix;
  final Color? backdropColor;
  final int? position;

  const ExThumbnail({
    super.key,
    required this.imageUrl,
    this.videoPath = '',
    required this.width,
    required this.height,
    this.iconSize = 64,
    this.fitMemory = BoxFit.cover,
    this.fitUrl = BoxFit.fitHeight,
    this.withProxy = true,
    this.prefix = 1,
    this.backdropColor,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(_ExThumbnailC());

    if (imageUrl == null || imageUrl == '') {
      return FutureBuilder<Uint8List?>(
        future: controller.getThumbnail(videoPath ?? '', position: position),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Icon(
              Icons.broken_image,
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
      final double fastImageRenderWidth = width * (prefix ?? 1);

      return OverflowBox(
        alignment: Alignment.centerRight,
        maxWidth: fastImageRenderWidth,
        maxHeight: height,
        child: CachedNetworkImage(
          key: Key(withProxy == true ? '${imageUrl?.genImageUrl()}' : '${imageUrl ?? ''}'),
          imageUrl: withProxy == true ? '${imageUrl?.genImageUrl()}' : '${imageUrl ?? ''}',
          fit: fitUrl,
          width: fastImageRenderWidth,
          height: height,
          fadeInDuration: 300.milliseconds,
          cacheManager: CacheManager(
            Config(
              'net_thumbnail',
              stalePeriod: 365.days,
              maxNrOfCacheObjects: (pow(2, 63) - 1).toInt(),
              repo: CacheObjectProvider(
                databaseName: 'net_thumbnail',
                path: p.join(Get.find<AppSettingService>().appPath, 'net_thumbnail'),
              ),
            ),
          ),
          progressIndicatorBuilder: (context, url, progress) {
            return Stack(
              children: [
                Container(
                  width: width,
                  height: height,
                  color: Vx.neutral800,
                ).shimmer(primaryColor: Vx.neutral800, secondaryColor: Vx.neutral900),
                if (progress.progress != null) ...[
                  ' ${(progress.progress! * 100).toDoubleStringAsFixed(digit: 0)}%'.text.xs.align(TextAlign.center).makeCentered(),
                ]
              ],
            );
          },
          errorWidget: (context, error, stackTrace) {
            return Icon(
              Icons.broken_image,
              size: iconSize,
            ).wh(width, height).centered().color(AppColor.selected);
          },
        ),
      ).color(backdropColor ?? AppColor.container).wh(width, height);
    }
  }
}
