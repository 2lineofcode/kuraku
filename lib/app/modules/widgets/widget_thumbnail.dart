import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:uicons_pro/uicons_pro.dart';
import 'package:video_compress/video_compress.dart';

import '../../core/app_color.dart';
import '../../core/app_logging.dart';
import '../../core/app_setting.dart';
import '../../utils/helper_misc.dart';

class _ExThumbnailC extends GetxController {
  // ---- caches & inflight
  final Map<String, Uint8List> _memCache = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  final Map<String, String> _codecCache = {};

  // ---- limiters
  static final _ffmpegLimiter = _AsyncLimiter(2); // ffmpeg max 2 proses bareng (aman buat HDD)
  static final _videoCompressLimiter = _AsyncLimiter(1); // video_compress max 1 (biar gak freeze)

  // ---- timeouts
  static const _vcTimeout = Duration(seconds: 45); // matiin job video_compress yg ngegantung
  static const _ffTimeout = Duration(seconds: 15); // cancel ffmpeg kalau kelamaan

  Future<String> _thumbDir() async {
    final appPath = Get.find<AppSettingService>().appPath;
    final dir = p.join(appPath, 'vid_thumbnail');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  String _thumbName(String videoPath) => '${p.basenameWithoutExtension(videoPath)}.jpg';

  // ---- detect codec via ffmpeg (process)
  Future<String?> _detectCodec(String videopath) async {
    // final isExternal = videopath.startsWith('/Volumes/') || videopath.startsWith('/media/');
    // if (isExternal) return '';

    if (_codecCache.containsKey(videopath)) return _codecCache[videopath];
    try {
      final result = await Process.run(
        '/usr/local/bin/ffmpeg',
        ['-hide_banner', '-loglevel', 'info', '-i', videopath],
        runInShell: false,
      );
      final out = '${result.stdout}${result.stderr}';
      final codec = _parseCodecFromOutput(out);
      _codecCache[videopath] = codec;
      AppLog.logD('[thumb] codec=$codec');
      return codec;
    } catch (e) {
      AppLog.logE('[thumb] detect codec fail (process): $e');
      _codecCache[videopath] = '';
      return '';
    }
  }

  String _parseCodecFromOutput(String logs) {
    final lower = logs.toLowerCase();
    final match = RegExp(r'video:\s*([a-z0-9]+)').firstMatch(lower);
    return match?.group(1) ?? '';
  }

  // ---- ffmpeg thumbnail with timeout & cancel
  Future<Uint8List?> _thumbWithFfmpeg(
    String inputPath,
    String outPath, {
    required int seconds,
  }) async {

    // ✅ skip kalau file gak ada (misal drive eject, file rusak, dll)
    final f = File(inputPath);
    if (!f.existsSync()) return null;


    return _ffmpegLimiter.run(() async {
      // fast seek + keyframe-only decoding → jauh lebih cepat
      final cmd = [
        '-hide_banner',
        '-nostdin',
        '-loglevel', 'panic',
        '-y',
        '-ss', _fmtSec(seconds), // fast seek (kurang akurat dikit, cukup buat thumbnail)
        '-skip_frame', 'nokey', // decode keyframe saja
        '-threads', '1', // hindari kontensi di HDD
        '-i', '"$inputPath"',
        '-frames:v', '1',
        '"$outPath"',
      ].join(' ');

      final completer = Completer<Uint8List?>();
      Timer? killer;

      // jalanin async biar bisa cancel
      final session = await FFmpegKit.executeAsync(cmd, (s) async {
        // selesai normal
        killer?.cancel();
        final rc = await s.getReturnCode();
        if (ReturnCode.isSuccess(rc) && await File(outPath).exists()) {
          completer.complete(await File(outPath).readAsBytes());
        } else {
          AppLog.logE('[thumb] ffmpeg fail: ${await s.getOutput()}');
          completer.complete(null);
        }
      });

      // watchdog timeout → cancel session
      killer = Timer(_ffTimeout, () async {
        try {
          final id = session.getSessionId();
          await FFmpegKit.cancel(id);
          AppLog.logW('[thumb] ⏰ ffmpeg timeout, canceled session $id');
        } catch (e, stackTrace) {
          AppLog.logD('[thumb] ffmpeg timeout cancel failed: $e');
          AppLog.logD('$stackTrace');
        }
        if (!completer.isCompleted) completer.complete(null);
      });

      final res = await completer.future;
      return res;
    });
  }

  String _fmtSec(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec.000';
  }

  // ---- safe video_compress with timeout
  Future<Uint8List?> _safeVideoCompress(String inputPath, int pos) async {

    // ✅ skip kalau file gak ada (misal drive eject, file rusak, dll)
    final f = File(inputPath);
    if (!f.existsSync()) return null;

    try {
      return await _videoCompressLimiter.run(() async {
        return await VideoCompress.getByteThumbnail(inputPath, quality: 5, position: pos).timeout(_vcTimeout, onTimeout: () {
          AppLog.logW('[thumb] ⏰ video_compress timeout: $inputPath');
          return null;
        });
      });
    } catch (e) {
      AppLog.logE('[thumb] video_compress error: $e');
      return null;
    }
  }

  // ---- public API
  Future<Uint8List?> getThumbnail(String videopath, {int? position}) {
    // inflight key pakai path#pos biar request posisi beda gak saling ngunci
    final pos = position ?? 90;
    final key = '$videopath#$pos';
    return _inflight[key] ??= _getThumbnailImpl(videopath, position: pos).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<Uint8List?> _getThumbnailImpl(String videopath, {required int position}) async {
    final isExternal = videopath.startsWith('/Volumes/') || videopath.startsWith('/media/');
   
    // RAM cache
    if (_memCache.containsKey(videopath) && position == 90) {
      return _memCache[videopath];
    }

    final dir = await _thumbDir();
    final filePath = p.join(dir, _thumbName(videopath));
    final file = File(filePath);

    // Disk cache
    if (await file.exists() && position == 90) {
      final bytes = await file.readAsBytes();
      _memCache[videopath] = bytes;
      return bytes;
    }

    final codec = (await _detectCodec(videopath)) ?? '';
    Uint8List? bytes;

    if (codec.contains('av1')) {
      AppLog.logW('[thumb] 🎥 AV1 → ffmpeg');
      bytes = await _thumbWithFfmpeg(videopath, filePath, seconds: position);
    } else {
      if (isExternal) {
        bytes = await _safeVideoCompress(videopath, position);
        if (bytes == null || bytes.isEmpty || bytes.length < 1000) {
          // AppLog.logW('[thumb] ⚠️ VC miss/timeout → ffmpeg (HDD)');
          // bytes = await _thumbWithFfmpeg(videopath, filePath, seconds: position);
        }
      } else {
        bytes = await _safeVideoCompress(videopath, position);
        if (bytes == null || bytes.isEmpty || bytes.length < 1000) {
          AppLog.logW('[thumb] ⚠️ fallback → ffmpeg (SSD)');
          bytes = await _thumbWithFfmpeg(videopath, filePath, seconds: position);
        }
      }
    }

    if (bytes != null && bytes.isNotEmpty && position == 90) {
      _memCache[videopath] = bytes;
      try {
        await file.writeAsBytes(bytes, flush: false);
      } catch (e, stackTrace) {
        AppLog.logD('[thumb] disk cache write failed: $e');
        AppLog.logD('$stackTrace');
      }
    }

    return bytes;
  }

  Future<void> clearDiskThumbnailCache() async {
    _memCache.clear();
    final dir = await _thumbDir();
    final d = Directory(dir);
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
  }
}

// ---- simple async limiter with queue
class _AsyncLimiter {
  final int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _queue = Queue();

  _AsyncLimiter(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= maxConcurrent) {
      final gate = Completer<void>();
      _queue.add(gate);
      await gate.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_queue.isNotEmpty) {
        _queue.removeFirst().complete();
      }
    }
  }
}

class ExThumbnail extends StatefulWidget {
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
  State<ExThumbnail> createState() => _ExThumbnailState();
}

class _ExThumbnailState extends State<ExThumbnail> {
  late final _ExThumbnailC controller;

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<_ExThumbnailC>()
        ? Get.find<_ExThumbnailC>()
        : Get.put(_ExThumbnailC(), permanent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl == '') {
      return FutureBuilder<Uint8List?>(
        key: ValueKey('${widget.videoPath}#${widget.position ?? 90}'),
        future: controller.getThumbnail(widget.videoPath ?? '', position: widget.position),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Icon(UIconsPro.regularRounded.loading, size: 32).wh(widget.width, widget.height).centered().color(AppColor.selected);
          }
          return (snap.hasData && snap.data != null)
              ? Image.memory(
                  snap.data!,
                  fit: widget.fitMemory,
                  width: widget.width,
                  height: widget.height,
                )
              : Icon(Icons.broken_image, size: widget.iconSize).wh(widget.width, widget.height).centered().color(AppColor.selected);
        },
      );
    }

    var fixImageUrl = widget.imageUrl!;
    if (widget.imageUrl!.endsWith('ps.jpg')) {
      fixImageUrl = widget.imageUrl!.replaceAll('ps.jpg', 'pl.jpg');
    }

    final double fastImageRenderWidth = widget.width * (widget.prefix ?? 1);
    return OverflowBox(
      alignment: Alignment.centerRight,
      maxWidth: fastImageRenderWidth,
      maxHeight: widget.height,
      child: CachedNetworkImage(
        key: Key(widget.withProxy == true ? '${fixImageUrl.genImageUrl()}' : '$fixImageUrl'),
        imageUrl: widget.withProxy == true ? '${fixImageUrl.genImageUrl()}' : '$fixImageUrl',
        fit: widget.fitUrl,
        width: fastImageRenderWidth,
        height: widget.height,
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
        progressIndicatorBuilder: (c, url, progress) => Stack(children: [
          Container(width: widget.width, height: widget.height, color: Vx.neutral800).shimmer(primaryColor: Vx.neutral800, secondaryColor: Vx.neutral900),
          if (progress.progress != null) ' ${(progress.progress! * 100).toDoubleStringAsFixed(digit: 0)}%'.text.xs.align(TextAlign.center).makeCentered(),
        ]),
        errorWidget: (c, e, s) => Icon(Icons.broken_image, size: widget.iconSize).wh(widget.width, widget.height).centered().color(AppColor.selected),
      ),
    ).color(widget.backdropColor ?? AppColor.container).wh(widget.width, widget.height);
  }
}
