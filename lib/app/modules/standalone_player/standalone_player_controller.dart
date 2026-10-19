import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:ex_kit/ex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/app_translations.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper_file_picker.dart';
import '../../utils/helper_misc.dart';
import '../../utils/helper_toast.dart';
import 'standalone_player_seek_preview.dart';

class StandalonePlayerController extends GetxController with StateMixin<Videos>, GetSingleTickerProviderStateMixin {
  final focusSignal = 0.obs;

  late final Player player;
  late final VideoController videoController;

  final currentVideo = Videos().obs;
  final currentIndexPlaying = 0.obs;
  final playlist = <Videos>[].obs;

  final isInitialized = false.obs;
  final isFullScreen = false.obs;
  final showPlaybackControls = true.obs;
  final infoOverlayText = ''.obs;
  final videoFit = BoxFit.contain.obs;
  final videoZoom = 1.0.obs;
  final videoPan = Offset.zero.obs;
  Offset _appliedVideoPan = Offset.zero;
  Size _panViewport = Size.zero;
  Future<void> _zoomUpdate = Future<void>.value();
  double _appliedVideoZoom = 1;
  final isPlayerVisible = false.obs;
  final isDropHovering = false.obs;

  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final volume = 1.0.obs;
  final playbackSpeed = 1.0.obs;
  final bufferingPercent = 0.0.obs;
  final isAudioNormalizationEnabled = false.obs;
  Map<String, double>? customAdjustment;
  final videoAdjustments = <String, double>{'brightness': 0, 'contrast': 0, 'saturation': 0, 'hue': 0, 'gamma': 0};
  String adjustmentPreset = 'Custom';

  late AnimationController infoAnimationController;

  final _subscriptions = <StreamSubscription>[];
  bool _isAutoAdvancing = false;
  bool _openingVideo = false;
  int _playbackRevision = 0;

  bool _isCurrentPlayback(int revision) => revision == _playbackRevision && !isClosed && _shutdown == null;

  List<Videos>? _externalPlaylist;
  static const subtitleExtensions = ['srt', 'vtt', 'ass', 'ssa'];
  Future<void>? _playerInitialization;

  @override
  void onInit() {
    super.onInit();
    infoAnimationController = AnimationController(vsync: this, duration: 1.seconds, reverseDuration: 200.milliseconds);
    change(currentVideo.value, status: RxStatus.loading());
  }

  Future<void> initializePlayer() async {
    player = Player(
      configuration: PlayerConfiguration(
        vo: 'libmpv',
        logLevel: MPVLogLevel.debug,
        title: 'Player',
        ready: () => debugPrint('player is ready'),
      ),
    );

    if (player.platform is NativePlayer) {
      final p = player.platform as NativePlayer;
      await p.setProperty('vo', 'libmpv');
      await p.setProperty('hwdec', 'auto-safe');
      await p.setProperty('opengl-hwdec-interop', 'auto');

      await p.setProperty('video-sync', 'display-resample');
      await p.setProperty('interpolation', 'no');
      await p.setProperty('framedrop', 'decoder+vo');
      await p.setProperty('autosync', '0');
      await p.setProperty('correct-pts', 'yes');
      await p.setProperty('demuxer-thread', 'yes');

      await p.setProperty('hr-seek', 'no');
      await p.setProperty('hr-seek-demuxer', 'yes');
      await p.setProperty('hr-seek-framedrop', 'yes');

      await p.setProperty('cache', 'auto');
      await p.setProperty('cache-secs', '60');
      await p.setProperty('cache-pause', 'no');
      await p.setProperty('demuxer-readahead-secs', '5');
      await p.setProperty('demuxer-lavf-o', 'seek_timestamp=1');
    }

    videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: 'libmpv',
        hwdec: 'auto-safe',
      ),
    );
    WidgetsBinding.instance.ensureVisualUpdate();

    _bindPlayerStreams();
    await applyAudioNormalization(enabled: isAudioNormalizationEnabled.value);
  }

  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) async {
    if (isClosed || _shutdown != null) return false;

    final path = video.videoPath;
    if (path.isNullOrEmpty) {
      await HelperToast.error('Video path is null'.tr, addToAppLog: false);
      return false;
    }

    if (_openingVideo || _shutdown != null) return false;
    _openingVideo = true;
    final revision = ++_playbackRevision;
    try {
      final exists = await File(path!).exists();
      if (!_isCurrentPlayback(revision)) return false;
      if (!exists) {
        await HelperToast.error('Cant access file: @{videoPath}'.trNamed({'videoPath': path}), addToAppLog: false);
        return false;
      }
      await (_playerInitialization ??= initializePlayer());
      if (!_isCurrentPlayback(revision)) return false;
      if (!await _openVideo(video, revision) || !_isCurrentPlayback(revision)) return false;
      _externalPlaylist = playlist;
      currentVideo.value = video;

      await generatePlaylist();
      if (!_isCurrentPlayback(revision) || !identical(currentVideo.value, video)) return false;

      isPlayerVisible.value = true;
      change(video, status: RxStatus.success());
      requestFocusOnPlayer();
      return true;
    } catch (e) {
      debugPrint('Failed to start playback: $e');
      if (_shutdown == null) await HelperToast.error('Failed to load video: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
      return false;
    } finally {
      _openingVideo = false;
    }
  }

  Future<void> stopPlayback() async {
    _playbackRevision++;
    playlist.clear();
    _externalPlaylist = null;
    currentVideo.value = Videos();
    isPlayerVisible.value = false;
    bufferingPercent.value = 0;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    change(currentVideo.value, status: RxStatus.loading());
    try { await player.stop(); }
    catch (_) {}
  }

  void onDropEnter(DropEvent event) => isDropHovering.value = true;
  void onDropLeave(DropEvent event) => isDropHovering.value = false;
  void onDropEnded(DropEvent event) => isDropHovering.value = false;

  Future<void> onDropEvent(PerformDropEvent event) async {
    if (isClosed || _shutdown != null) return;
    isDropHovering.value = false;
    final video = currentVideo.value;
    final revision = _playbackRevision;
    final readTasks = <Future<String?>>[];

    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;

      final completer = Completer<String?>();
      readTasks.add(completer.future);

      reader.getValue<Uri>(Formats.fileUri, (data) {
        completer.complete(data == null ? null : _normalizeDropPath(data));
      }, onError: (error) {
        debugPrint('Failed to read dropped file: $error');
        completer.complete(null);
      });
    }

    final droppedPaths = (await Future.wait(readTasks)).whereType<String>().toSet().toList();
    if (!_isCurrentPlayback(revision) || droppedPaths.isEmpty) return;

    // macOS keeps its native drag operation open until this callback returns.
    unawaited(Future<void>(() async {
      if (!_isCurrentPlayback(revision)) return;
      try {
        await _processDroppedPaths(droppedPaths, video, revision);
      } catch (e) {
        debugPrint('Failed to process dropped files: $e');
        if (_isCurrentPlayback(revision)) {
          await HelperToast.error('Failed to load video: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
        }
      }
    }));
  }

  Future<void> _processDroppedPaths(List<String> droppedPaths, Videos video, int revision) async {
    final videoPaths = <String>[];
    final subtitlePaths = <String>[];
    var hasUnsupportedFile = false;

    for (final path in droppedPaths) {
      final isFile = await FileSystemEntity.isFile(path);
      if (!isFile) {
        hasUnsupportedFile = true;
        continue;
      }

      if (HelperFilePicker.isSupportedVideoPath(path)) {
        videoPaths.add(path);
      } else if (subtitleExtensions.contains(extension(path).toLowerCase().replaceFirst('.', ''))) {
        subtitlePaths.add(path);
      } else {
        hasUnsupportedFile = true;
      }
    }

    if (!_isCurrentPlayback(revision)) return;

    if (subtitlePaths.isNotEmpty) {
      if (subtitlePaths.length != 1 || videoPaths.isNotEmpty) {
        await HelperToast.warn('Drop one subtitle file onto the current video'.tr, addToAppLog: false);
      } else if (identical(currentVideo.value, video)) {
        await loadSubtitle(subtitlePaths.single);
      }
      return;
    }

    if (videoPaths.isEmpty) {
      if (hasUnsupportedFile) {
        await HelperToast.warn('File not supported'.tr, addToAppLog: false);
      }
      return;
    }

    await _openDroppedVideos(videoPaths);
  }

  Future<void> pickVideos() async {
    if (isClosed || _shutdown != null) return;
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Open files'.tr,
        type: FileType.custom,
        allowedExtensions: HelperFilePicker.videoExtensions,
      );
      if (isClosed || _shutdown != null || files.isEmpty) return;
      await openFiles(files.map((file) => file.path).whereType<String>().toList());
    } catch (e) {
      debugPrint('Failed to open video picker: $e');
      await HelperToast.error('Failed to load video: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
    } finally {
      requestFocusOnPlayer();
    }
  }

  Future<void> openFiles(List<String> paths) async {
    if (isClosed || _shutdown != null) return;
    final supported = paths.where(HelperFilePicker.isSupportedVideoPath).toSet().toList();
    if (supported.isEmpty) {
      await HelperToast.warn('File not supported'.tr, addToAppLog: false);
      return;
    }
    await _openDroppedVideos(supported);
  }

  Future<void> pickSubtitle() async {
    final video = currentVideo.value;
    try {
      final result = await FilePicker.pickFile(
        dialogTitle: 'Load subtitle'.tr,
        type: FileType.custom,
        allowedExtensions: subtitleExtensions,
      );
      final path = result?.path;
      if (path != null && !isClosed && identical(currentVideo.value, video)) await loadSubtitle(path);
    } catch (e) {
      debugPrint('Failed to open subtitle picker: $e');
      await HelperToast.error('Failed to open subtitle: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
    } finally {
      requestFocusOnPlayer();
    }
  }

  Future<void> loadSubtitle(String path) async {
    if (isClosed || _shutdown != null) return;
    try {
      if (!subtitleExtensions.contains(extension(path).toLowerCase().replaceFirst('.', ''))) {
        throw ArgumentError('Supported subtitles: .srt, .vtt, .ass, .ssa'.tr);
      }
      if (!File(path).existsSync()) throw FileSystemException('Cannot access subtitle'.tr, path);
      await selectSubtitle(SubtitleTrack.uri(Uri.file(path).toString(), title: basename(path)));
    } catch (e) {
      debugPrint('Failed to load subtitle ($path): $e');
      await HelperToast.error('Failed to load subtitle: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
    }
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    if (isClosed || _shutdown != null || !isInitialized.value || !isPlayerVisible.value) return;
    try {
      await player.setSubtitleTrack(track);
    } catch (e) {
      debugPrint('Failed to select subtitle track: $e');
      await HelperToast.error('Failed to select subtitle: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
    } finally {
      requestFocusOnPlayer();
    }
  }

  String _normalizeDropPath(Uri uri) {
    try {
      return uri.toFilePath();
    } catch (_) {
      return Uri.decodeFull(uri.path);
    }
  }

  String _normalizeRawDropPath(String rawPath) {
    final value = rawPath.trim();
    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    if (uri.scheme == 'file') {
      try {
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
        ).toFilePath();
      } catch (_) {
        return Uri.decodeFull(uri.path);
      }
    }

    return value;
  }

  Future<void> _openDroppedVideos(List<String> paths) async {
    final revision = _playbackRevision;
    final videos = <Videos>[];
    for (final path in paths) {
      final video = await _createDroppedVideo(path);
      if (!_isCurrentPlayback(revision)) return;
      if (video != null) {
        videos.add(video);
      }
    }

    if (!_isCurrentPlayback(revision) || videos.isEmpty) return;
    await startPlayback(videos.first, playlist: videos);
  }

  Future<Videos?> _createDroppedVideo(String path) async {
    final decodedPath = _normalizeRawDropPath(path);
    final file = File(decodedPath);

    final fileName = basename(decodedPath);
    final cleanTitle = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        await HelperToast.warn('File not found'.tr, addToAppLog: false);
        return null;
      }
      return Videos(
        videoPath: decodedPath,
        title: cleanTitle,
        filesize: stat.size,
      );
    } catch (e) {
      if (!isClosed && _shutdown == null) await HelperToast.error('Cant access video file'.tr, addToAppLog: false);
      return null;
    }
  }

  void _bindPlayerStreams() {
    _subscriptions.add(player.stream.position.listen((value) => position.value = value));
    _subscriptions.add(player.stream.duration.listen((value) => duration.value = value));
    _subscriptions.add(player.stream.playing.listen((value) {
      isPlaying.value = value;
    }));
    _subscriptions.add(player.stream.buffering.listen((value) {
      isBuffering.value = value;
    }));
    _subscriptions.add(player.stream.bufferingPercentage.listen((value) => bufferingPercent.value = value));

    _subscriptions.add(player.stream.volume.listen((value) {
      final normalized = (value / 100.0).clamp(0.0, 1.0);
      volume.value = normalized;
    }));

    _subscriptions.add(player.stream.rate.listen((value) {
      playbackSpeed.value = value;
    }));

    _subscriptions.add(player.stream.width.listen((value) {
      if (value != null && value > 0) isInitialized.value = true;
    }));

    _subscriptions.add(player.stream.height.listen((value) {
      if (value != null && value > 0) isInitialized.value = true;
    }));

    _subscriptions.add(player.stream.error.listen((value) async {
      if (value.isEmpty) return;
      if (_shouldIgnoreNoAudioError(value)) {
        debugPrint('Ignored player no-audio error: $value');
        return;
      }
      await HelperToast.error(value, addToAppLog: false);
    }));

    _subscriptions.add(player.stream.completed.listen((value) async {
      if (value != true || _isAutoAdvancing) return;
      _isAutoAdvancing = true;
      isPlaying.value = false;
      try {
        if (currentIndexPlaying.value >= 0 && currentIndexPlaying.value + 1 < playlist.length) await nextVideo();
      } finally {
        _isAutoAdvancing = false;
      }
    }));
  }

  bool _shouldIgnoreNoAudioError(String message) {
    final msg = message.toLowerCase();
    final isNoAudio = msg.contains('no audio')
        || msg.contains('audio track')
        || msg.contains('audio stream')
        || msg.contains('failed to initialize audio')
        || msg.contains('audio output')
        || msg.contains('audio filter initialized failed')
        || msg.contains('audio filter init failed')
        || msg.contains('option af: dynaudnorm doesn\'t exist')
        || msg.contains('option af:')
        || msg.contains('[ao]')
        || msg.contains('ao/');
    return isNoAudio;
  }

  Future<bool> _openVideo(Videos video, int revision) async {
    final path = video.videoPath;
    if (path.isNullOrEmpty) {
      await HelperToast.error('Video path is null'.tr, addToAppLog: false);
      return false;
    }

    final exists = await File(path!).exists();
    if (!_isCurrentPlayback(revision)) return false;
    if (!exists) {
      await HelperToast.warn('Cant access video file'.tr, addToAppLog: false);
      return false;
    }

    try {
      isInitialized.value = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      await setVideoZoom(1);
      if (!_isCurrentPlayback(revision)) return false;

      await player.open(
        Media(Uri.file(path).toString()),
        play: true,
      );

      if (!_isCurrentPlayback(revision)) {
        if (_shutdown == null) await player.stop();
        return false;
      }
      await applyAudioNormalization(enabled: isAudioNormalizationEnabled.value);
      if (!_isCurrentPlayback(revision)) return false;
      await player.setRate(playbackSpeed.value);
      if (!_isCurrentPlayback(revision)) return false;
      await player.setVolume(volume.value * 100);
      if (!_isCurrentPlayback(revision)) return false;
      try {
        await videoController.waitUntilFirstFrameRendered.timeout(3.seconds, onTimeout: () => null);
      } catch (_) {}
      if (!_isCurrentPlayback(revision)) return false;
      isInitialized.value = true;
      return true;
    } catch (e) {
      if (!_isCurrentPlayback(revision)) return false;
      try { await player.stop(); } catch (_) {}
      isPlaying.value = false;
      isInitialized.value = false;
      debugPrint('Failed to load video: $e');
      await HelperToast.error('Failed to load video: @{e}'.trNamed({'e': '$e'}), addToAppLog: false);
      return false;
    }
  }

  Future<void> setVideoZoom(double scale) {
    if (!scale.isFinite || scale <= 0) return Future<void>.value();
    final platform = player.platform;
    if (platform is! NativePlayer) return Future<void>.value();
    final target = scale.clamp(1.0, 4.0);
    videoZoom.value = target;
    _zoomUpdate = _zoomUpdate.then((_) async {
      if (videoZoom.value != target) return;
      try {
        await platform.setProperty('video-zoom', (math.log(target) / math.ln2).toString());
        _appliedVideoZoom = target;
      } catch (e) {
        if (videoZoom.value == target) videoZoom.value = _appliedVideoZoom;
        debugPrint('Video zoom failed: $e');
      }
    });
    if (target == 1) {
      _panViewport = Size.zero;
      return setVideoPan(Offset.zero);
    }
    if (!_panViewport.isEmpty) return panVideo(Offset.zero, _panViewport);
    return _zoomUpdate;
  }

  Future<void> panVideo(Offset delta, Size viewport) {
    if (videoZoom.value <= 1 || viewport.isEmpty || !viewport.width.isFinite || !viewport.height.isFinite || !delta.dx.isFinite || !delta.dy.isFinite) return Future<void>.value();
    _panViewport = viewport;
    final width = (player.state.width ?? 0) > 0 ? player.state.width!.toDouble() : viewport.width;
    final height = (player.state.height ?? 0) > 0 ? player.state.height!.toDouble() : viewport.height;
    final fitScale = videoFit.value == BoxFit.fitHeight ? viewport.height / height : math.min(viewport.width / width, viewport.height / height);
    final scaled = Size(width * fitScale * videoZoom.value, height * fitScale * videoZoom.value);
    if (scaled.isEmpty) return Future<void>.value();
    final maxX = math.max(0.0, (scaled.width - viewport.width) / (2 * scaled.width));
    final maxY = math.max(0.0, (scaled.height - viewport.height) / (2 * scaled.height));
    return setVideoPan(Offset(
      (videoPan.value.dx + delta.dx / scaled.width).clamp(-maxX, maxX),
      (videoPan.value.dy + delta.dy / scaled.height).clamp(-maxY, maxY),
    ));
  }

  Future<void> setVideoPan(Offset offset) {
    if (!offset.dx.isFinite || !offset.dy.isFinite) return Future<void>.value();
    final platform = player.platform;
    if (platform is! NativePlayer) return Future<void>.value();
    final limit = videoZoom.value > 1 ? .5 : 0.0;
    final target = Offset(offset.dx.clamp(-limit, limit), offset.dy.clamp(-limit, limit));
    videoPan.value = target;
    _zoomUpdate = _zoomUpdate.then((_) async {
      if (videoPan.value != target) return;
      try {
        await platform.setProperty('video-pan-x', target.dx.toString());
        await platform.setProperty('video-pan-y', target.dy.toString());
        _appliedVideoPan = target;
      } catch (e) {
        if (videoPan.value == target) videoPan.value = _appliedVideoPan;
        try {
          await platform.setProperty('video-pan-x', _appliedVideoPan.dx.toString());
          await platform.setProperty('video-pan-y', _appliedVideoPan.dy.toString());
        } catch (rollback) { debugPrint('Video pan rollback failed: $rollback'); }
        debugPrint('Video pan failed: $e');
      }
    });
    return _zoomUpdate;
  }

  Future<void> setVolumeNormalized(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    volume.value = normalized;
    await player.setVolume(normalized * 100);
  }

  Future<void> applyAudioNormalization({required bool enabled}) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      isAudioNormalizationEnabled.value = enabled;
      return;
    }

    if (!enabled) {
      try {
        await platform.setProperty('af', '');
      } catch (e) {
        debugPrint('disable audio normalization failed: $e');
      }
      isAudioNormalizationEnabled.value = false;
      return;
    }

    const candidates = <String>[
      'lavfi=[acompressor=threshold=-18dB:ratio=3:attack=10:release=180:makeup=4dB]',
      'lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]',
      'lavfi=[alimiter=limit=0.95]',
    ];

    var applied = false;
    for (final filter in candidates) {
      try {
        await platform.setProperty('af', filter);
        applied = true;
        break;
      } catch (e) {
        debugPrint('audio normalization candidate failed ($filter): $e');
      }
    }

    if (!applied) {
      try {
        await platform.setProperty('af', '');
      } catch (_) {}
      isAudioNormalizationEnabled.value = false;
      debugPrint('Audio normalization unsupported. Disabled automatically.');
      return;
    }

    isAudioNormalizationEnabled.value = true;
  }

  Future<void> adjustVolume(double delta) async {
    await setVolumeNormalized(volume.value + delta);
  }

  Future<void> mute() async {
    await setVolumeNormalized(0.0);
  }

  Future<void> setPlaybackRate(double value) async {
    final clamped = value.clamp(0.25, 3.0);
    playbackSpeed.value = clamped;
    await player.setRate(clamped);
  }

  Future<void> adjustPlaybackRate(double delta) async {
    await setPlaybackRate(playbackSpeed.value + delta);
  }

  Future<void> togglePlayPause() async {
    if (isPlaying.value) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration target) async {
    final total = duration.value;
    final clamped = _clampDuration(
      target,
      Duration.zero,
      total > Duration.zero ? total : target,
    );

    final p = player.platform as NativePlayer;
    await p.seek(clamped, synchronized: true);
  }

  Future<void> seekRelative(Duration offset) async {
    final player = this.player;
    if (player.platform is NativePlayer) {
      final p = player.platform as NativePlayer;
      final seconds = offset.inSeconds.toString();
      await p.command(['seek', seconds, 'relative']);
    } else {
      await seek(position.value + offset);
    }
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (max > min && value > max) return max;
    return value;
  }

  Future<void> generatePlaylist() async {
    final video = currentVideo.value;
    playlist.assignAll(_externalPlaylist?.isNotEmpty == true ? _externalPlaylist! : [video]);
    currentIndexPlaying.value = playlist.indexWhere((element) => element.videoPath == video.videoPath);
  }

  Future<void> openList() async {
    if (isClosed || _shutdown != null) return;
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      requestFocusOnPlayer();
      return;
    }

    final search = TextEditingController();
    final searchFocus = FocusNode();
    final videos = playlist.toList().obs;
    final scroll = ScrollController();
    var closed = false;

    void scrollToCurrent() {
      if (!scroll.hasClients) return;
      final index = videos.indexWhere((video) => video.videoPath == currentVideo.value.videoPath);
      scroll.jumpTo((math.max(index, 0) * 128.0).clamp(0.0, scroll.position.maxScrollExtent));
    }

    Widget action(IconData icon, String tooltip, VoidCallback onPressed, {Color color = Colors.white70}) => Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero, minimumSize: const Size.square(32),
        onPressed: onPressed, child: Icon(icon, size: 16, color: color),
      ),
    );

    WidgetsBinding.instance.scheduleFrame();
    try {
      await Overlayment.show(
        context: Get.context,
        OverPanel(
          alignment: Alignment.centerRight,
          width: math.min(360, MediaQuery.sizeOf(Get.context!).width),
          color: Colors.transparent,
          animation: OverSlideAnimation(
            beginAlignment: Alignment.centerRight,
            reverseDurationMilliseconds: 100,
            durationMilliseconds: 400,
          ),
          actions: OverlayActions(
            onReady: () async { scrollToCurrent(); searchFocus.requestFocus(); },
            onClose: (_) async { closed = true; searchFocus.unfocus(); requestFocusOnPlayer(); },
          ),
          child: CupertinoTheme(
            data: const CupertinoThemeData(brightness: Brightness.dark, primaryColor: Colors.white),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E).withValues(alpha: .58),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('Playlist'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white))),
                        Obx(() => Text('${videos.length}', style: const TextStyle(fontSize: 12, color: Colors.white54))),
                        const SizedBox(width: 8),
                        action(CupertinoIcons.xmark, 'Close'.tr, () => Overlayment.dismissLast()),
                      ]),
                      const SizedBox(height: 12),
                      CupertinoSearchTextField(
                        controller: search, focusNode: searchFocus,
                        placeholder: 'Search playlist'.tr,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        placeholderStyle: const TextStyle(fontSize: 12, color: Colors.white54),
                        itemColor: Colors.white54, itemSize: 16,
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        onChanged: (query) {
                          if (query.isNotEmpty) return;
                          videos.assignAll(playlist);
                          WidgetsBinding.instance.addPostFrameCallback((_) { if (!closed) scrollToCurrent(); });
                        },
                        onSubmitted: (query) {
                          final q = query.trim();
                          if (q.isEmpty) return;
                          final term = q.toLowerCase();
                          videos.assignAll(playlist.where((item) => '${item.title} ${item.videoPath}'.toLowerCase().contains(term)));
                          if (scroll.hasClients) scroll.jumpTo(0);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(child: Obx(() => videos.isEmpty
                        ? Center(child: Text('No videos found'.tr, style: const TextStyle(fontSize: 12, color: Colors.white54)))
                        : ListView.builder(
                          controller: scroll, itemExtent: 128, itemCount: videos.length,
                          itemBuilder: (context, index) {
                            final item = videos[index];
                            final selected = item.videoPath == currentVideo.value.videoPath;
                            final metadata = [
                              if ((item.filesize ?? 0) > 0) item.filesize!.toFileSizeFormat(),
                            ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Tooltip(
                                message: 'Double-click to play'.tr,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onDoubleTap: () async {
                                    if (selected) return;
                                    final path = item.videoPath;
                                    if (path == null || path.isEmpty || !File(path).existsSync()) {
                                      await HelperToast.warn('Cant access video file'.tr, addToAppLog: false);
                                      return;
                                    }
                                    await Overlayment.dismissLast();
                                    await changeVideo(item);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: selected ? Colors.white.withValues(alpha: .12) : Colors.white.withValues(alpha: .03),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: selected ? Colors.white30 : Colors.transparent),
                                    ),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      _PlaylistThumbnail(key: ValueKey(item.videoPath), path: item.videoPath ?? ''),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          if (selected) ...[const Icon(CupertinoIcons.play_fill, size: 10, color: Colors.white), const SizedBox(width: 6)],
                                          Expanded(child: Text(item.title ?? basename(item.videoPath ?? ''),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
                                        ]),
                                        const Spacer(),
                                        Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                      ])),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      closed = true;
      search.dispose();
      searchFocus.dispose();
      scroll.dispose();
      requestFocusOnPlayer();
    }
  }

  Future<void> changeVideo(Videos newVideo) async {
    if (_openingVideo || _shutdown != null) return;
    _openingVideo = true;
    final revision = ++_playbackRevision;
    try {
      if (!await _openVideo(newVideo, revision) || !_isCurrentPlayback(revision)) return;
      currentVideo.value = newVideo;
      await generatePlaylist();
      if (!_isCurrentPlayback(revision) || !identical(currentVideo.value, newVideo)) return;
      change(newVideo, status: RxStatus.success());
      requestFocusOnPlayer();
    } finally {
      _openingVideo = false;
    }
    await showInfoOverlay('${currentIndexPlaying.value + 1}/${playlist.length}');
  }

  Future<void> showInfoOverlay(String text) async {
    if (isClosed || _shutdown != null) return;
    infoOverlayText.value = text;
    if (infoAnimationController.isAnimating || infoAnimationController.isCompleted) {
      infoAnimationController.reset();
    }
    await infoAnimationController.forward().then((_) async {
      await Future.delayed(1500.milliseconds);
      if (!isClosed && _shutdown == null) await infoAnimationController.reverse();
    });
  }

  Future<void> toggleVideoFit() async {
    videoFit.value = videoFit.value == BoxFit.contain ? BoxFit.fitHeight : BoxFit.contain;
    final label = videoFit.value == BoxFit.contain ? 'Fit: Contain'.tr : 'Fit: Fit Height'.tr;
    await showInfoOverlay(label);
  }

  Future<void> nextVideo() async {
    if (currentIndexPlaying.value + 1 >= playlist.length) return;
    await changeVideo(playlist[currentIndexPlaying.value + 1]);
  }

  Future<void> prevVideo() async {
    if (currentIndexPlaying.value - 1 < 0) return;
    await changeVideo(playlist[currentIndexPlaying.value - 1]);
  }

  bool _fullscreenTransition = false;
  VideoState? _fullscreenState;

  Future<void> exitFullscreen() async {
    final state = _fullscreenState;
    if (state != null && state.isFullscreen()) await toggleFullscreen(state);
  }

  Future<void> toggleFullscreen(VideoState state) async {
    if (_fullscreenTransition) return;
    _fullscreenTransition = true;
    try {
      Tooltip.dismissAllToolTips();
      await WidgetsBinding.instance.endOfFrame;
      final isCurrentlyFullScreen = state.isFullscreen();
      debugPrint('toggleFullscreen: currently fullscreen = $isCurrentlyFullScreen');
      if (isCurrentlyFullScreen) {
        await state.exitFullscreen();
        _fullscreenState = null;
        isFullScreen.value = false;
        debugPrint('toggleFullscreen: exited fullscreen');
      } else {
        await state.enterFullscreen();
        _fullscreenState = state;
        isFullScreen.value = true;
        debugPrint('toggleFullscreen: entered fullscreen');
      }

      await WidgetsBinding.instance.endOfFrame;
      await Get.forceAppUpdate();
    } catch (e) {
      debugPrint('toggleFullscreen error: $e');
    } finally {
      _fullscreenTransition = false;
      requestFocusOnPlayer();
    }
  }

  Future<void>? _shutdown;

  Future<void> shutdown() => _shutdown ??= _disposePlayer();

  Future<void> _disposePlayer() async {
    try {
      if (_playerInitialization != null) {
        try { await _playerInitialization; }
        catch (e) { debugPrint('Player initialization failed before disposal: $e'); }
        for (final subscription in _subscriptions) { await subscription.cancel(); }
        if (player.platform is NativePlayer) await _zoomUpdate;
        await player.dispose();
      }
    } catch (e) {
      debugPrint('Failed to dispose player: $e');
    } finally {
      infoAnimationController.dispose();
    }
  }

  @override
  Future<void> onClose() async {
    await shutdown();
    super.onClose();
  }

  void requestFocusOnPlayer() {
    if (isClosed || _shutdown != null) return;
    focusSignal.value++;
  }
}

class _PlaylistThumbnail extends StatefulWidget {
  const _PlaylistThumbnail({super.key, required this.path});

  final String path;

  @override
  State<_PlaylistThumbnail> createState() => _PlaylistThumbnailState();
}

class _PlaylistThumbnailState extends State<_PlaylistThumbnail> {
  final _preview = StandalonePlayerSeekPreview();

  @override
  void initState() {
    super.initState();
    _preview.request(widget.path, 0);
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 88, height: 64,
      child: AnimatedBuilder(
        animation: _preview,
        builder: (context, _) {
          final bytes = _preview.bytes;
          if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          return _preview.isLoading
            ? const Center(child: CupertinoActivityIndicator(color: Colors.white54))
            : const Icon(CupertinoIcons.film, color: Colors.white54);
        },
      ),
    ),
  );
}
