import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show pow;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:super_context_menu/super_context_menu.dart' as scm;
import 'package:uicons_pro/uicons_pro.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_compress/video_compress.dart';

import '../../../env.g.dart';
import '../../core/app_color.dart';
import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../core/app_setting.dart';
import '../../data/api/api_javit.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/videos_entity.dart';
import '../../modules/home/home_controller.dart';
import '../../modules/home/home_panel/home_panel_metadata.dart';
import '../../modules/home/home_panel/home_panel_playlist.dart';
import '../../utils/helper.dart';

class _ExThumbnailC extends GetxController {
  // ---- caches & inflight
  final Map<String, Uint8List> _memCache = {};
  final Map<String, Uint8List> _previewMemCache = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  final Map<String, String> _codecCache = {};

  // ---- limiters
  static final _ffmpegLimiter = _AsyncLimiter(2); // ffmpeg max 2 proses bareng (aman buat HDD)
  static final _videoCompressLimiter = _AsyncLimiter(1); // video_compress max 1 (biar gak freeze)

  // ---- timeouts
  static const _vcTimeout = Duration(seconds: 45); // matiin job video_compress yg ngegantung
  static const _vcPreviewTimeout = Duration(seconds: 8); // short timeout for screenshot previews
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
        '-update', '1', // single image output, avoid image2 sequence warning
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
  Future<Uint8List?> _safeVideoCompress(String inputPath, int pos, {Duration timeout = _vcTimeout}) async {

    // ✅ skip kalau file gak ada (misal drive eject, file rusak, dll)
    final f = File(inputPath);
    if (!f.existsSync()) return null;

    try {
      return await _videoCompressLimiter.run(() async {
        return await VideoCompress.getByteThumbnail(inputPath, quality: 5, position: pos).timeout(timeout, onTimeout: () {
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
    final rawPos = position ?? 90;
    final pos = rawPos == 90 ? 90 : _normalizePreviewPosition(rawPos);
    final key = '$videopath#$pos';

    if (pos != 90 && _previewMemCache.containsKey(key)) {
      return Future.value(_previewMemCache[key]);
    }

    return _inflight[key] ??= _getThumbnailImpl(videopath, position: pos).whenComplete(() {
      _inflight.remove(key);
    });
  }

  int _normalizePreviewPosition(int seconds) {
    if (seconds <= 0) return 0;
    return (seconds ~/ 10) * 10;
  }

  void _setPreviewCache(String key, Uint8List bytes) {
    _previewMemCache[key] = bytes;
    if (_previewMemCache.length > 180) {
      _previewMemCache.remove(_previewMemCache.keys.first);
    }
  }

  void _setThumbnailCache(String key, Uint8List bytes) {
    _memCache[key] = bytes;
    if (_memCache.length > 180) {
      _memCache.remove(_memCache.keys.first);
    }
  }

  Future<Uint8List?> _getThumbnailImpl(String videopath, {required int position}) async {
    final isExternal = videopath.startsWith('/Volumes/') || videopath.startsWith('/media/');
    final cacheKey = '$videopath#$position';

    // Screenshot previews use video_compress only, without ffmpeg fallback.
    if (position != 90) {
      final bytes = await _safeVideoCompress(videopath, position, timeout: _vcPreviewTimeout);
      if (bytes != null && bytes.isNotEmpty && bytes.length > 1000) {
        _setPreviewCache(cacheKey, bytes);
        return bytes;
      }
      return null;
    }
   
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
      _setThumbnailCache(videopath, bytes);
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
      } else {
        bytes = await _safeVideoCompress(videopath, position);
        if (bytes == null || bytes.isEmpty || bytes.length < 1000) {
          AppLog.logW('[thumb] ⚠️ fallback → ffmpeg (SSD)');
          bytes = await _thumbWithFfmpeg(videopath, filePath, seconds: position);
        }
      }
    }

    if (bytes != null && bytes.isNotEmpty && position == 90) {
      _setThumbnailCache(videopath, bytes);
      try {
        await file.writeAsBytes(bytes, flush: false);
      } catch (e, stackTrace) {
        AppLog.logD('[thumb] disk cache write failed: $e');
        AppLog.logD('$stackTrace');
      }
    }

    return bytes;
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
  final String? videoCode;
  final double width;
  final double height;
  final double? iconSize;
  final BoxFit? fitMemory;
  final BoxFit? fitUrl;
  final bool? withProxy;
  final double? prefix;
  final Color? backdropColor;
  final int? position;
  final scm.ContextMenuIsAllowed? contextMenuIsAllowed;

  const ExThumbnail({
    super.key,
    required this.imageUrl,
    this.videoPath = '',
    this.videoCode = '',
    required this.width,
    required this.height,
    this.iconSize = 64,
    this.fitMemory = BoxFit.cover,
    this.fitUrl = BoxFit.fitHeight,
    this.withProxy = true,
    this.prefix = 1,
    this.backdropColor,
    this.position,
    this.contextMenuIsAllowed,
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

  String _deriveVideoCode() {
    final fromWidget = HelperMisc.resolveVideoCode(videoCode: widget.videoCode, videoPath: widget.videoPath);
    if (fromWidget.isNotEmpty) return fromWidget;

    final fromImage = (widget.imageUrl ?? '').trim();
    if (fromImage.isEmpty) return '';
    final raw = fromImage.split('?').first;
    var base = p.basenameWithoutExtension(raw);
    if (base.endsWith('ps') || base.endsWith('pl')) {
      base = base.substring(0, base.length - 2);
    }
    return base.getVideoCode();
  }

  Future<Videos?> _findVideoByPath() async {
    final path = (widget.videoPath ?? '').trim();
    if (path.isEmpty) return null;
    return DBVideos.getByVideoPath(path);
  }

  Future<void> _refreshMetadata(Videos video) async {
    final code = HelperMisc.resolveVideoCode(videoCode: video.videoCode, videoPath: video.videoPath, title: video.title);
    if (!code.isValidVideoCode()) {
      await HelperToast.warn('Video code not valid');
      return;
    }

    HelperLoading.show();
    try {
      final resp = await ApiJavit.getMetadata(code: code);
      final newVideo = video;
      newVideo.videoCode = HelperMisc.resolveVideoCode(videoCode: resp.videoCode, title: code);

      newVideo.title = resp.title;
      newVideo.titleJa = resp.titleJa;
      newVideo.description = resp.description;
      newVideo.fanArt = resp.fanArt?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideo.poster = resp.poster?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideo.trailer = resp.trailer;
      newVideo.site = 'R18';

      if (video.actress.isEmptyOrNull && !resp.actress.isEmptyOrNull) {
        newVideo.actress = <VideoActress>[];
        for (var i = 0; i < resp.actress!.length; i++) {
          newVideo.actress?.add(
            VideoActress(
              id: resp.actress![i].castId,
              nameRomaji: resp.actress![i].castNames,
              imageUrl: resp.actress![i].castImage,
            ),
          );
        }
      }

      newVideo.category = <VideoCategory>[];
      if (resp.genre != null) {
        for (var i = 0; i < resp.genre!.length; i++) {
          newVideo.category?.add(VideoCategory(id: i, category: resp.genre![i]));
        }
      }

      newVideo.releaseDate = resp.releaseDate;
      newVideo.releaseDateFormated = resp.releaseDateFormated;
      newVideo.duration = resp.duration;
      newVideo.durationFormated = resp.durationFormated;
      newVideo.studio = resp.studio;
      newVideo.label = resp.label;
      newVideo.director = resp.director;
      newVideo.series = resp.series;

      newVideo.screenshot = <String>[];
      if (resp.screenshot != null) {
        for (var i = 0; i < resp.screenshot!.length; i++) {
          final shot = resp.screenshot![i].toString();
          if (shot.contains('jp-')) {
            newVideo.screenshot?.add(shot.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', ''));
          } else {
            newVideo.screenshot?.add(shot.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '').replaceAll('-', 'jp-'));
          }
        }
      }

      await DBVideos.update(newVideo);
      await HelperToast.success('$code metadata updated');
    } catch (e) {
      await HelperToast.error(e.toString());
    } finally {
      HelperLoading.dismiss();
    }
  }

  Future<void> _openDownloadByCode(String code) async {
    AppLog.logD('code -> $code');
    if (!code.isValidVideoCode()) {
      await HelperToast.warn('Video code not valid');
      return;
    }

    final searchEngine = AppPref.getDefaultSearchEngine();
    switch (searchEngine.toLowerCase()) {
      case 'njav':
        await launchUrlString('${Env.njavUrl}/$code');
        break;
      case 'missav':
        await launchUrlString('${Env.missavUrl}/$code');
        break;
      case 'javmost':
        await launchUrlString('${Env.javmostUrl}/$code');
        break;
      case 'sextb':
        await launchUrlString('${Env.sextbUrl}/$code');
        break;
      case 'javguru':
        await launchUrlString('${Env.javguruUrl}/?s=$code');
        break;
      default:
        await launchUrlString('${Env.njavUrl}/$code');
        break;
    }
  }

  Future<scm.Menu?> _buildContextMenu() async {
    final path = (widget.videoPath ?? '').trim();
    final videoCode = _deriveVideoCode();
    final hasVideoPath = path.isNotEmpty;
    final dbVideo = hasVideoPath ? await _findVideoByPath() : null;
    if (!mounted) return null;

    scm.MenuAction action(String title, String value) => scm.MenuAction(
      title: title,
      callback: () async {
        if (!mounted) return;
        try {
          await _handleContextMenuAction(value, path, dbVideo, videoCode);
        } catch (e) {
          await HelperToast.error(e.toString());
        }
      },
    );

    return scm.Menu(children: hasVideoPath
        ? [
            action('Play', 'play'),
            action('Add to Panel Cart', 'add_panel_cart'),
            scm.MenuSeparator(),
            action((dbVideo?.isFavorite ?? 0) == 1 ? 'Remove From Favorite' : 'Add To Favorite', 'favorite'),
            action('Add to Playlist', 'add_playlist'),
            scm.MenuSeparator(),
            action('Edit Metadata', 'edit_metadata'),
            action('Refresh Metadata', 'refresh_metadata'),
            action('Open File Path', 'open_file_path'),
          ]
        : [
            action('Download', 'download'),
            action('Open Screenshot', 'open_screenshot'),
            action('Open Trailer', 'open_trailer'),
          ],
    );
  }

  Future<void> _handleContextMenuAction(String selected, String path, Videos? dbVideo, String videoCode) async {
    switch (selected) {
      case 'play':
        if (dbVideo != null) {
          await HelperOpener.openVideoFile(dbVideo);
          return;
        }
        if (!File(path).existsSync()) {
          await HelperToast.warn('File not found');
          return;
        }
        await HelperOpener.openVideoFile(Videos(videoPath: path, title: p.basenameWithoutExtension(path)));
        break;
      case 'favorite':
        if (dbVideo == null) {
          await HelperToast.warn('Video not found in database');
          break;
        }
        if ((dbVideo.isFavorite ?? 0) == 1) {
          await DBVideos.removeFromFavorite(dbVideo);
          await HelperToast.info('Removed from favorite');
        } else {
          await DBVideos.addToFavorite(dbVideo);
          await HelperToast.success('Added to favorite');
        }
        break;
      case 'add_playlist':
      case 'edit_metadata':
        if (dbVideo == null) {
          await HelperToast.warn('Video not found in database');
          break;
        }
        if (selected == 'add_playlist') {
          await HomePanelPlaylist.showDialogAddToPlaylistItem([dbVideo]);
        } else {
          await HomePanelMetadata.open(dbVideo);
        }
        break;
      case 'refresh_metadata':
        if (dbVideo == null) {
          await HelperToast.warn('Video not found in database');
          break;
        }
        await _refreshMetadata(dbVideo);
        break;
      case 'open_file_path':
        await HelperOpener.openFilePath(path);
        break;
      case 'add_panel_cart':
        if (dbVideo == null) {
          await HelperToast.warn('Video not found in database');
          break;
        }
        final home = Get.find<HomeController>();
        final isAdded = home.addToCart(dbVideo);
        if (isAdded) {
          await HelperToast.success('Added to cart');
        } else {
          await HelperToast.warn('Already in panel cart');
        }
        break;
      case 'download':
        await _openDownloadByCode(videoCode);
        break;
      case 'open_screenshot':
        await HelperOpener.openScreenshot({'video_code': videoCode});
        break;
      case 'open_trailer':
        await HelperOpener.openTrailer({'video_code': videoCode});
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (widget.width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget child;
    if ((widget.imageUrl ?? '').trim().isEmpty) {
      child = FutureBuilder<Uint8List?>(
        future: controller.getThumbnail(widget.videoPath ?? '', position: widget.position),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            if (snap.hasData && snap.data != null) {
              return Image.memory(
                snap.data!,
                fit: widget.fitMemory,
                width: widget.width,
                height: widget.height,
                cacheWidth: cacheWidth,
              );
            }
            return Icon(UIconsPro.regularRounded.loading, size: 32).wh(widget.width, widget.height).centered().color(AppColor.selected);
          }
          return (snap.hasData && snap.data != null)
              ? Image.memory(
                  snap.data!,
                  fit: widget.fitMemory,
                  width: widget.width,
                  height: widget.height,
                  cacheWidth: cacheWidth,
                )
              : Icon(Icons.broken_image, size: widget.iconSize).wh(widget.width, widget.height).centered().color(AppColor.selected);
        },
      );
    } else {
      final fixImageUrl = widget.imageUrl!.trim();

      final double fastImageRenderWidth = widget.width * (widget.prefix ?? 1);
      child = OverflowBox(
        alignment: Alignment.centerRight,
        maxWidth: fastImageRenderWidth,
        maxHeight: widget.height,
        child: CachedNetworkImage(
          key: Key(widget.withProxy == true ? '${fixImageUrl.genImageUrl()}' : '$fixImageUrl'),
          imageUrl: widget.withProxy == true ? '${fixImageUrl.genImageUrl()}' : '$fixImageUrl',
          fit: widget.fitUrl,
          width: fastImageRenderWidth,
          height: widget.height,
          memCacheWidth: (fastImageRenderWidth * MediaQuery.devicePixelRatioOf(context)).round(),
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

    return scm.ContextMenuWidget(
      hitTestBehavior: HitTestBehavior.opaque,
      menuProvider: (_) => _buildContextMenu(),
      contextMenuIsAllowed: widget.contextMenuIsAllowed ?? (_) => true,
      child: child,
    );
  }
}
