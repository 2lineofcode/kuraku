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
import 'package:uuid/v4.dart';

import '../../core/app_identity.dart';
import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../core/app_translations.dart';
import '../../data/database/db_activity.dart';
import '../../data/database/db_gamification.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';
import '../../utils/semantic_search_service.dart';
import '../../utils/watch_session_tracker.dart';
import '../home/home_controller.dart';
import '../home/home_panel/home_panel_video_info.dart';
import '../home/page_home/page_home_controller.dart';
import '../widgets/widget_thumbnail.dart';

class PlayerController extends GetxController with StateMixin<Videos>, GetSingleTickerProviderStateMixin {
  final count = 0.obs;
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
  final isMiniMode = false.obs;
  final isPlayerVisible = false.obs;
  final isDropHovering = false.obs;

  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final volume = AppPref.getPlayerVolume().obs;
  final playbackSpeed = AppPref.getPlayerSpeed().obs;
  final bufferingPercent = 0.0.obs;
  final isAudioNormalizationEnabled = AppPref.getPlayerAudioNormalization().obs;

  late AnimationController infoAnimationController;

  final _subscriptions = <StreamSubscription>[];
  double _lastPersistedVolume = AppPref.getPlayerVolume();
  double _lastPersistedSpeed = AppPref.getPlayerSpeed();
  bool _hasSyncedPreferences = false;
  bool _isAutoAdvancing = false;

  final _watchTracker = WatchSessionTracker();
  bool _watchVideoReady = false;

  void _syncWatchState() {
    _watchTracker.setPlaying(_watchVideoReady && player.state.playing && !player.state.buffering);
  }

  Future<void> _persistWatchDuration() async {
    try {
      await _watchTracker.flush();
      if (!_watchVideoReady && currentVideo.value.id == null) return;
      if (Get.isRegistered<HomeController>()) {
        await Get.find<HomeController>().refreshProfile();
      } else {
        await DBGamification.syncAndGetSummary();
      }
    } catch (e) {
      AppLog.logW('Failed to save watch duration: $e');
    }
  }

  List<Videos>? _externalPlaylist;
  static const subtitleExtensions = ['srt', 'vtt', 'ass', 'ssa'];
  static const _supportedDropVideoExtensions = {'mp4', 'mkv', 'avi', 'mov'};
  Future<void>? _playerInitialization;
  Worker? _semanticPlaybackWorker;
  bool _semanticPlaybackActive = false;

  @override
  void onInit() {
    super.onInit();
    _semanticPlaybackWorker = ever(isPlayerVisible, (visible) {
      if (visible == _semanticPlaybackActive) return;
      _semanticPlaybackActive = visible;
      if (visible) {
        SemanticSearchService.beginPlayback();
      } else {
        SemanticSearchService.endPlayback();
      }
    });

    infoAnimationController = AnimationController(vsync: this, duration: 1.seconds, reverseDuration: 200.milliseconds);
    change(currentVideo.value, status: RxStatus.loading());
  }

  Future<void> _initializePlayer() async {
    player = Player(
      configuration: PlayerConfiguration(
        vo: 'libmpv',
        logLevel: MPVLogLevel.debug,
        title: AppIdentity.displayName,
        ready: () => AppLog.logD('player is ready'),
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

      //
      await p.setProperty('hr-seek', 'no');
      await p.setProperty('hr-seek-demuxer', 'yes');
      await p.setProperty('hr-seek-framedrop', 'yes');

      //
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

    _bindPlayerStreams();
    await applyAudioNormalization(enabled: isAudioNormalizationEnabled.value, persist: false);
  }

  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) async {

    // check maxColi Count
    final todayColi = await DBActivity.getCountRelapseToday();
    AppLog.logD('todayColi -> $todayColi');
    if (todayColi >= AppPref.getAppMaxColi()) {
      await HelperToast.error('Max coli count reached for today. Please try again tomorrow.'.tr);
      Get.back();
      return false;
    }


    final path = video.videoPath;
    if (path.isNullOrEmpty) {
      await HelperToast.error('Video path is null'.tr);
      return false;
    }

    final decodedPath = Uri.parse(path!).toFilePath();
    final file = File(decodedPath);
    if (!file.existsSync()) {
      await HelperToast.error('Cant access file: @{videoPath}'.trNamed({'videoPath': '${video.videoPath}'}));
      return false;
    }

    await (_playerInitialization ??= _initializePlayer());
    _externalPlaylist = playlist;
    currentVideo.value = video;

    await DBVideos.updateViewCount(currentVideo.value);
    await generatePlaylist();
    currentIndexPlaying.value = this.playlist.indexWhere((element) => element.id == currentVideo.value.id);

    await _openVideo(currentVideo.value);

    isPlayerVisible.value = true;
    isMiniMode.value = false;
    change(currentVideo.value, status: RxStatus.success());
    requestFocusOnPlayer();
    return true;
  }

  Future<void> stopPlayback() async {
    _watchVideoReady = false;
    _watchTracker.setPlaying(false);
    await _persistWatchDuration();
    try { await player.stop(); }
    catch (_) {}
    playlist.clear();
    _externalPlaylist = null;
    currentVideo.value = Videos();
    isPlayerVisible.value = false;
    isMiniMode.value = false;
    bufferingPercent.value = 0;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    change(currentVideo.value, status: RxStatus.loading());
  }

  void onDropEnter(DropEvent event) => isDropHovering.value = true;
  void onDropLeave(DropEvent event) => isDropHovering.value = false;
  void onDropEnded(DropEvent event) => isDropHovering.value = false;

  Future<void> onDropEvent(PerformDropEvent event) async {
    isDropHovering.value = false;
    final video = currentVideo.value;
    final droppedPaths = <String>[];
    final readTasks = <Future<void>>[];

    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;

      final completer = Completer<void>();
      readTasks.add(completer.future);

      reader.getValue<Uri>(Formats.fileUri, (data) {
        if (data != null) {
          droppedPaths.add(_normalizeDropPath(data));
        }
        completer.complete();
      });
    }

    await Future.wait(readTasks);
    if (droppedPaths.isEmpty) return;

    final videoPaths = <String>[];
    final subtitlePaths = <String>[];
    var hasUnsupportedFile = false;

    for (final path in droppedPaths) {
      final isFile = await FileSystemEntity.isFile(path);
      if (!isFile) {
        hasUnsupportedFile = true;
        continue;
      }

      if (_isVideoPath(path)) {
        videoPaths.add(path);
      } else if (subtitleExtensions.contains(extension(path).toLowerCase().replaceFirst('.', ''))) {
        subtitlePaths.add(path);
      } else {
        hasUnsupportedFile = true;
      }
    }

    if (subtitlePaths.isNotEmpty) {
      if (subtitlePaths.length != 1 || videoPaths.isNotEmpty) {
        await HelperToast.warn('Drop one subtitle file onto the current video'.tr);
      } else if (identical(currentVideo.value, video)) {
        await loadSubtitle(subtitlePaths.single);
      }
      return;
    }

    if (videoPaths.isEmpty) {
      if (hasUnsupportedFile) {
        await HelperToast.warn('File not supported'.tr);
      }
      return;
    }

    if (videoPaths.length == 1) {
      await _openDroppedVideo(videoPaths.first);
      return;
    }

    await _openDroppedVideos(videoPaths);
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
      AppLog.logW('Failed to open subtitle picker: $e');
      await HelperToast.error('Failed to open subtitle: @{e}'.trNamed({'e': '$e'}));
    } finally {
      requestFocusOnPlayer();
    }
  }

  Future<void> loadSubtitle(String path) async {
    try {
      if (!subtitleExtensions.contains(extension(path).toLowerCase().replaceFirst('.', ''))) {
        throw ArgumentError('Supported subtitles: .srt, .vtt, .ass, .ssa'.tr);
      }
      if (!File(path).existsSync()) throw FileSystemException('Cannot access subtitle'.tr, path);
      await selectSubtitle(SubtitleTrack.uri(Uri.file(path).toString(), title: basename(path)));
    } catch (e) {
      AppLog.logW('Failed to load subtitle ($path): $e');
      await HelperToast.error('Failed to load subtitle: @{e}'.trNamed({'e': '$e'}));
    }
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    if (isClosed || !isInitialized.value || !isPlayerVisible.value) return;
    try {
      await player.setSubtitleTrack(track);
    } catch (e) {
      AppLog.logW('Failed to select subtitle track: $e');
      await HelperToast.error('Failed to select subtitle: @{e}'.trNamed({'e': '$e'}));
    } finally {
      requestFocusOnPlayer();
    }
  }

  void enterMiniMode() {
    if (isPlayerVisible.isFalse) return;
    isMiniMode.value = true;
  }

  void exitMiniMode() {
    isMiniMode.value = false;
  }

  bool _isVideoPath(String path) {
    if (!path.contains('.')) return false;

    final ext = path.toLowerCase().split('.').last;
    return _supportedDropVideoExtensions.contains(ext);
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

  Future<void> _openDroppedVideo(String path) async {
    final video = await _createDroppedVideo(path);
    if (video == null) return;

    await HelperOpener.openVideoFile(video);
  }

  Future<void> _openDroppedVideos(List<String> paths) async {
    final videos = <Videos>[];
    for (final path in paths) {
      final video = await _createDroppedVideo(path);
      if (video != null) {
        videos.add(video);
      }
    }

    if (videos.isEmpty) return;
    await HelperOpener.openVideoFile(videos.first, playlist: videos);
  }

  Future<Videos?> _createDroppedVideo(String path) async {
    final decodedPath = _normalizeRawDropPath(path);
    final file = File(decodedPath);
    if (!file.existsSync()) {
      await HelperToast.warn('File not found'.tr);
      return null;
    }

    final fileName = decodedPath.getLastPath();
    final cleanTitle = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

    return Videos(
      id: UuidV4().generate(),
      videoPath: decodedPath,
      videoCode: decodedPath.getFileName().getVideoCode(),
      title: cleanTitle,
      viewCount: 0,
      filesize: await file.length(),
      createdAt: DateTime.now().toStringEx(),
      updatedAt: DateTime.now().toStringEx(),
    );
  }

  void _bindPlayerStreams() {
    _subscriptions.add(player.stream.position.listen((value) => position.value = value));
    _subscriptions.add(player.stream.duration.listen((value) => duration.value = value));
    _subscriptions.add(player.stream.playing.listen((value) {
      isPlaying.value = value;
      _watchTracker.setPlaying(_watchVideoReady && value && !isBuffering.value);
    }));
    _subscriptions.add(player.stream.buffering.listen((value) {
      isBuffering.value = value;
      _watchTracker.setPlaying(_watchVideoReady && isPlaying.value && !value);
    }));
    _subscriptions.add(player.stream.bufferingPercentage.listen((value) => bufferingPercent.value = value));

    _subscriptions.add(player.stream.volume.listen((value) {
      final normalized = (value / 100.0).clamp(0.0, 1.0);
      volume.value = normalized;
      if (_hasSyncedPreferences && (normalized - _lastPersistedVolume).abs() > 0.01) {
        _lastPersistedVolume = normalized;
        AppPref.setPlayerVolume(normalized);
      }
    }));

    _subscriptions.add(player.stream.rate.listen((value) {
      playbackSpeed.value = value;
      if (_hasSyncedPreferences && (value - _lastPersistedSpeed).abs() > 0.01) {
        _lastPersistedSpeed = value;
        AppPref.setPlayerSpeed(value);
      }
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
        AppLog.logD('Ignored player no-audio error: $value');
        return;
      }
      await HelperToast.error(value);
    }));

    _subscriptions.add(player.stream.completed.listen((value) async {
      if (value != true || _isAutoAdvancing) return;
      _isAutoAdvancing = true;
      isPlaying.value = false;
      _watchTracker.setPlaying(false);
      try {
        await _persistWatchDuration();
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

  Future<void> _openVideo(Videos video) async {
    final path = video.videoPath;
    if (path.isNullOrEmpty) {
      await HelperToast.error('Video path is null'.tr);
      return;
    }

    final file = File(path!);
    if (!file.existsSync()) {
      await HelperToast.warn('Cant access video file'.tr);
      return;
    }

    _watchVideoReady = false;
    _watchTracker.setVideo(video);

    try {
      isInitialized.value = false;
      _hasSyncedPreferences = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      await setVideoZoom(1);

      await player.open(
        Media(Uri.file(path).toString()),
        play: true,
      );

      _watchVideoReady = true;
      _syncWatchState();
      await applyAudioNormalization(enabled: isAudioNormalizationEnabled.value, persist: false);
      await player.setRate(playbackSpeed.value);
      await player.setVolume(volume.value * 100);
      _hasSyncedPreferences = true;
      try {
        await videoController.waitUntilFirstFrameRendered.timeout(3.seconds, onTimeout: () => null);
      } catch (_) {}
      isInitialized.value = true;
    } catch (e) {
      _watchVideoReady = false;
      _watchTracker.setPlaying(false);
      isInitialized.value = false;
      AppLog.logE('Failed to load video: $e');
      await HelperToast.error('Failed to load video: @{e}'.trNamed({'e': '$e'}));
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
        AppLog.logW('Video zoom failed: $e');
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
        } catch (rollback) { AppLog.logW('Video pan rollback failed: $rollback'); }
        AppLog.logW('Video pan failed: $e');
      }
    });
    return _zoomUpdate;
  }

  Future<void> setVolumeNormalized(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    volume.value = normalized;
    _lastPersistedVolume = normalized;
    AppPref.setPlayerVolume(normalized);
    _hasSyncedPreferences = true;
    await player.setVolume(normalized * 100);
  }

  Future<void> applyAudioNormalization({required bool enabled, bool persist = true}) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      isAudioNormalizationEnabled.value = enabled;
      if (persist) AppPref.setPlayerAudioNormalization(enabled);
      return;
    }

    if (!enabled) {
      try {
        await platform.setProperty('af', '');
      } catch (e) {
        AppLog.logD('disable audio normalization failed: $e');
      }
      isAudioNormalizationEnabled.value = false;
      if (persist) AppPref.setPlayerAudioNormalization(false);
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
        AppLog.logD('audio normalization candidate failed ($filter): $e');
      }
    }

    if (!applied) {
      try {
        await platform.setProperty('af', '');
      } catch (_) {}
      isAudioNormalizationEnabled.value = false;
      AppPref.setPlayerAudioNormalization(false);
      AppLog.logW('Audio normalization unsupported. Disabled automatically.');
      return;
    }

    isAudioNormalizationEnabled.value = true;
    if (persist) AppPref.setPlayerAudioNormalization(true);
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
    _lastPersistedSpeed = clamped;
    AppPref.setPlayerSpeed(clamped);
    _hasSyncedPreferences = true;
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
    playlist.clear();
    final initialPlaylist = _externalPlaylist;
    if (initialPlaylist != null && initialPlaylist.isNotEmpty) {
      playlist.addAll(initialPlaylist);
    } else if ((currentVideo.value.videoPath ?? '').isNotEmpty) {
      final directoryVideos = await DBVideos.getAllVideoPath('video_path', dirname(currentVideo.value.videoPath!));
      playlist.addAll(directoryVideos);
    }
    currentIndexPlaying.value = playlist.indexWhere((element) => element.id == currentVideo.value.id);
  }

  Future<void> addToCart() async {
    final homeController = Get.find<HomeController>();
    final isAdded = homeController.addToCart(currentVideo.value);
    if (!isAdded) {
      await HelperToast.info('Already in panel cart'.tr);
    } else {
      await HelperToast.success('Added in panel cart'.tr);
    }
    await Overlayment.dismissLast();
  }


  Future<void> openInfo() async {
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      requestFocusOnPlayer();
      return;
    }
    await HomePanelVideoInfo.open(currentVideo.value, items: playlist);
    requestFocusOnPlayer();
  }

  Future<void> openList() async {
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
    var request = 0;

    void scrollToCurrent() {
      if (!scroll.hasClients) return;
      final index = videos.indexWhere((video) => video.videoPath == currentVideo.value.videoPath);
      scroll.jumpTo((math.max(index, 0) * 128.0).clamp(0.0, scroll.position.maxScrollExtent));
    }

    Future<void> filter(Future<List<Videos>> result) async {
      final revision = ++request;
      try {
        final items = await result;
        if (closed || revision != request) return;
        videos.assignAll(items);
        if (scroll.hasClients) scroll.jumpTo(0);
      } catch (e) {
        if (closed || revision != request) return;
        AppLog.logE('Playlist search failed: $e');
        await HelperToast.error('Could not load videos. Please retry.'.tr);
      }
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
                        placeholder: 'Search library'.tr,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        placeholderStyle: const TextStyle(fontSize: 12, color: Colors.white54),
                        itemColor: Colors.white54, itemSize: 16,
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        onChanged: (query) {
                          if (query.isNotEmpty) return;
                          request++;
                          videos.assignAll(playlist);
                          WidgetsBinding.instance.addPostFrameCallback((_) { if (!closed) scrollToCurrent(); });
                        },
                        onSubmitted: (query) {
                          final q = query.trim();
                          if (q.isEmpty) return;
                          filter(DBVideos.getAll(
                            where: 'video_code LIKE ? OR title LIKE ? OR video_path LIKE ?',
                            whereArgs: ['%$q%', '%$q%', '%$q%'],
                          ));
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
                            final code = item.videoCode?.trim() ?? '';
                            final metadata = [
                              HelperMisc.formatVideoQuality(item.quality ?? '').maxWords(1),
                              if ((item.filesize ?? 0) > 0) item.filesize!.toFileSizeFormat(),
                              if (item.videoPath?.isHasUncensored() == true) 'RM',
                              if (item.videoPath?.isHasEnSub() == true) 'EN',
                              if (item.videoPath?.isHasIdSub() == true) 'ID',
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
                                      await HelperToast.warn('Cant access video file'.tr);
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
                                      ClipRRect(borderRadius: BorderRadius.circular(6), child: ExThumbnail(
                                        imageUrl: item.fanArt ?? '', videoPath: item.videoPath,
                                        width: 88, height: 64, fitUrl: BoxFit.cover, iconSize: 24,
                                      )),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          if (selected) ...[const Icon(CupertinoIcons.play_fill, size: 10, color: Colors.white), const SizedBox(width: 6)],
                                          Expanded(child: Text(code.isEmpty ? item.title ?? basename(item.videoPath ?? '') : code,
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
                                        ]),
                                        if (code.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.title ?? '',
                                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70))),
                                        const Spacer(),
                                        Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                        Row(children: [
                                          action(item.isFavorite == 1 ? CupertinoIcons.star_fill : CupertinoIcons.star,
                                            (item.isFavorite == 1 ? 'Remove from favorites' : 'Favorite').tr, () async {
                                              final favorite = item.isFavorite == 1;
                                              if (favorite) { await DBVideos.removeFromFavorite(item); }
                                              else { await DBVideos.addToFavorite(item); }
                                              item.isFavorite = favorite ? 0 : 1;
                                              if (!closed) videos.refresh();
                                              await Get.find<PageHomeController>().onRefresh();
                                            }, color: item.isFavorite == 1 ? Colors.orange : Colors.white70),
                                          action(CupertinoIcons.add, 'Add to Panel Cart'.tr, () async {
                                            final added = Get.find<HomeController>().addToCart(item);
                                            if (added) { await HelperToast.success('Added to panel cart'.tr); }
                                            else { await HelperToast.info('Already in panel cart'.tr); }
                                          }),
                                          if (!item.actress.isEmptyOrNull) action(CupertinoIcons.person, item.actress!.first.nameRomaji ?? '',
                                            () => filter(DBVideos.getByActress(item.actress!.first.nameRomaji ?? ''))),
                                          if (item.series.isNotEmptyAndNotNull) action(CupertinoIcons.tag, item.series!,
                                            () => filter(DBVideos.getBySeries(item.series!))),
                                        ]),
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
    currentVideo.value = newVideo;
    await _openVideo(newVideo);
    await generatePlaylist();
    await showInfoOverlay('${currentIndexPlaying.value + 1}/${playlist.length}');

    try {
      await DBVideos.updateViewCount(currentVideo.value);
    } catch (_) {}

    change(newVideo, status: RxStatus.success());
    requestFocusOnPlayer();
  }

  Future<void> showInfoOverlay(String text) async {
    infoOverlayText.value = text;
    if (infoAnimationController.isAnimating || infoAnimationController.isCompleted) {
      infoAnimationController.reset();
    }
    await infoAnimationController.forward().then((_) async {
      await Future.delayed(1500.milliseconds);
      await infoAnimationController.reverse();
    });
  }

  Future<void> toggleVideoFit() async {
    videoFit.value = videoFit.value == BoxFit.contain ? BoxFit.fitHeight : BoxFit.contain;
    final label = videoFit.value == BoxFit.contain ? 'Fit: Contain'.tr : 'Fit: Fit Height'.tr;
    await showInfoOverlay(label);
  }

  Future<void> nextVideo() async {
    if (currentIndexPlaying.value + 1 >= playlist.length) return;
    currentIndexPlaying.value++;
    await changeVideo(playlist[currentIndexPlaying.value]);
  }

  Future<void> prevVideo() async {
    if (currentIndexPlaying.value - 1 < 0) return;
    currentIndexPlaying.value--;
    await changeVideo(playlist[currentIndexPlaying.value]);
  }

  bool _fullscreenTransition = false;

  Future<void> toggleFullscreen(VideoState state) async {
    if (_fullscreenTransition) return;
    _fullscreenTransition = true;
    try {
      Tooltip.dismissAllToolTips();
      await WidgetsBinding.instance.endOfFrame;
      final isCurrentlyFullScreen = state.isFullscreen();
      AppLog.logD('toggleFullscreen: currently fullscreen = $isCurrentlyFullScreen');
      if (isCurrentlyFullScreen) {
        await state.exitFullscreen();
        isFullScreen.value = false;
        AppLog.logD('toggleFullscreen: exited fullscreen');
      } else {
        await state.enterFullscreen();
        isFullScreen.value = true;
        AppLog.logD('toggleFullscreen: entered fullscreen');
      }

      await WidgetsBinding.instance.endOfFrame;
      await Get.forceAppUpdate();
    } catch (e) {
      AppLog.logD('toggleFullscreen error: $e');
    } finally {
      _fullscreenTransition = false;
      requestFocusOnPlayer();
    }
  }

  Future<void> openSS() async {
    try {
      await HelperOpener.openScreenshot(currentVideo.value, items: playlist);
    } finally {
      requestFocusOnPlayer();
    }
  }

  @override
  Future<void> onClose() async {
    _watchVideoReady = false;
    try {
      try { await _watchTracker.close(); } catch (e) { AppLog.logW('Failed to close watch session: $e'); }
      await _persistWatchDuration();
    } finally {
      try {
        if (_playerInitialization != null) {
          await _playerInitialization;
          for (final subscription in _subscriptions) { await subscription.cancel(); }
          await _zoomUpdate;
          await player.dispose();
        }
      } finally {
        _semanticPlaybackWorker?.dispose();
        if (_semanticPlaybackActive) SemanticSearchService.endPlayback();
        _semanticPlaybackActive = false;
        infoAnimationController.dispose();
        super.onClose();
      }
    }
  }

  void requestFocusOnPlayer() {
    focusSignal.value++;
  }
}
