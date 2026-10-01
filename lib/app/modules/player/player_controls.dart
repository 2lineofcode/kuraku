import 'dart:async';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../utils/helper.dart';
import 'player_controller.dart';
import 'player_seek_preview.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.videoState,
    this.showTitle = true,
  });

  final PlayerController controller;
  final VideoState videoState;
  final bool showTitle;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  bool _focusRestorePending = false;
  final Duration _autoHideDuration = 2.seconds;

  Timer? _hideTimer;
  bool _controlsVisible = true;

  Timer? _infoTimer;
  late AnimationController _infoAnimationController;
  String _infoText = '';

  double? _scrubValue;
  double _pinchStartZoom = 1;
  double? _preMuteVolume;
  DateTime? _lastEqualPress;
  bool _isVolumePointerInside = false;
  bool _isVolumeDragging = false;
  bool _isSeekPreviewVisible = false;
  double _seekPreviewDx = 0;
  int _seekPreviewSecond = 0;
  final _seekPreview = PlayerSeekPreview();
  late final StreamSubscription _videoSubscription;

  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<int> _focusSubscription;

  OverPanel? _adjustmentsPanel;
  StateSetter? _rebuildAdjustments;
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  double _hue = 0;
  double _gamma = 0;
  String _activeAdjustmentPreset = 'Custom';
  bool _hasSavedCustomPreset = AppPref.hasPlayerCustomAdjustment();
  static const List<String> _videoPresetNames = [
    'Cinematic',
    'Vivid',
    'Noir',
    'Warm',
    'Cool',
    'Soft',
    'Punch',
    'Night',
    'Flat',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
    _infoAnimationController = AnimationController(
      vsync: this,
      duration: 200.milliseconds,
    );

    _playingSubscription = widget.controller.isPlaying.listen((playing) {
      if (playing) {
        _startHideTimer();
      } else {
        _showControls(permanent: true);
      }
    });
    _focusSubscription = widget.controller.focusSignal.listen((_) {
      _restoreFocus();
    });

    _videoSubscription = widget.controller.currentVideo.listen((_) {
      _seekPreview.clear();
      if (!mounted) return;
      setState(() {
        _isSeekPreviewVisible = false;
        _scrubValue = null;
      });
    });

    _restoreFocus();
  }

  void _restoreFocus({bool onlyIfScope = false}) {
    if (!mounted || _focusRestorePending) return;
    _focusRestorePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRestorePending = false;
      if (!mounted || Overlayment.count > 0 || ModalRoute.of(context)?.isCurrent == false) return;
      if (onlyIfScope && FocusManager.instance.primaryFocus is! FocusScopeNode) return;
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onFocusChanged() {
    // Recover an empty scope without stealing focus from inputs or dialogs.
    if (FocusManager.instance.primaryFocus is FocusScopeNode) _restoreFocus(onlyIfScope: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onFocusChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChanged);
    final panel = _adjustmentsPanel;
    _rebuildAdjustments = null;
    if (panel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Overlayment.dismiss(panel));
    }
    _hideTimer?.cancel();
    _infoTimer?.cancel();
    _seekPreview.dispose();
    _videoSubscription.cancel();
    _playingSubscription.cancel();
    _focusSubscription.cancel();
    _infoAnimationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    final shortcuts = <LogicalKeySet, Intent>{
      // Playback controls
      LogicalKeySet(LogicalKeyboardKey.space): PlayPauseIntent(),
      
      // Seeking
      LogicalKeySet(LogicalKeyboardKey.arrowRight): SeekForward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight): SeekForward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowRight): SeekForward60sIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): SeekBackward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft): SeekBackward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowLeft): SeekBackward60sIntent(),
      
      // Volume (ArrowUp conflicts with screenshot, so only ArrowDown)
      LogicalKeySet(LogicalKeyboardKey.arrowUp): VolumeUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowDown): VolumeDownIntent(),
      
      // Speed
      LogicalKeySet(LogicalKeyboardKey.bracketRight): SpeedUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.bracketLeft): SpeedDownIntent(),
      
      // Other
      LogicalKeySet(LogicalKeyboardKey.keyM): MuteIntent(),
      LogicalKeySet(LogicalKeyboardKey.equal): EqualTapIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyA): ToggleVideoFitIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyP): MiniPlayerIntent(),
      LogicalKeySet(LogicalKeyboardKey.comma): ToggleVideoAdjustmentsIntent(),
      
      // Navigation shortcuts from player_view
      LogicalKeySet(LogicalKeyboardKey.keyL): OpenListIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyQ): BackIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowUp): OpenScreenshotIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyI): OpenInfoIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyC): AddToCartIntent(),
      LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.greater): NextVideoIntent(),
      LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.less): PrevVideoIntent(),
    };

    final actions = <Type, Action<Intent>>{
      PlayPauseIntent: CallbackAction<PlayPauseIntent>( onInvoke: (intent) { _togglePlayPause(); return null; }, ),
      SeekForward5sIntent: CallbackAction<SeekForward5sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: AppPref.getPlayerSeekShort())); return null; }, ),
      SeekForward30sIntent: CallbackAction<SeekForward30sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: AppPref.getPlayerSeekMid())); return null; }, ),
      SeekForward60sIntent: CallbackAction<SeekForward60sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: AppPref.getPlayerSeekLong())); return null; }, ),
      SeekBackward5sIntent: CallbackAction<SeekBackward5sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: -AppPref.getPlayerSeekShort())); return null; }, ),
      SeekBackward30sIntent: CallbackAction<SeekBackward30sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: -AppPref.getPlayerSeekMid())); return null; }, ),
      SeekBackward60sIntent: CallbackAction<SeekBackward60sIntent>( onInvoke: (intent) { _seekRelative(Duration(seconds: -AppPref.getPlayerSeekLong())); return null; }, ),
      VolumeDownIntent: CallbackAction<VolumeDownIntent>( onInvoke: (intent) { _changeVolume(-0.05); return null; }, ),
      VolumeUpIntent: CallbackAction<VolumeUpIntent>( onInvoke: (intent) { _changeVolume(0.05); return null; }, ),
      SpeedUpIntent: CallbackAction<SpeedUpIntent>( onInvoke: (intent) { _changeSpeed(0.1); return null; }, ),
      SpeedDownIntent: CallbackAction<SpeedDownIntent>( onInvoke: (intent) { _changeSpeed(-0.1); return null; }, ),
      MuteIntent: CallbackAction<MuteIntent>( onInvoke: (intent) { _toggleMute(); return null; }, ),
      EqualTapIntent: CallbackAction<EqualTapIntent>( onInvoke: (intent) { _handleEqualPress(); return null; }, ),
      ToggleVideoFitIntent: CallbackAction<ToggleVideoFitIntent>( onInvoke: (intent) => widget.controller.toggleVideoFit() ),
      ToggleVideoAdjustmentsIntent: CallbackAction<ToggleVideoAdjustmentsIntent>( onInvoke: (intent) { _toggleVideoAdjustments(); return null; }, ),
      OpenListIntent: CallbackAction<OpenListIntent>( onInvoke: (intent) { widget.controller.openList(); return null; }, ),
      MiniPlayerIntent: CallbackAction<MiniPlayerIntent>( onInvoke: (intent) { widget.controller.enterMiniMode(); Get.back(); return null; }, ),
      BackIntent: CallbackAction<BackIntent>(onInvoke: (intent) { widget.controller.stopPlayback(); Get.back(); return null; }),
      OpenScreenshotIntent: CallbackAction<OpenScreenshotIntent>( onInvoke: (intent) { widget.controller.openSS(); return null; } ),
      OpenInfoIntent: CallbackAction<OpenInfoIntent>( onInvoke: (intent) { widget.controller.openInfo(); return null; }, ),
      AddToCartIntent: CallbackAction<AddToCartIntent>( onInvoke: (intent) { widget.controller.addToCart(); return null; }, ),
      NextVideoIntent: CallbackAction<NextVideoIntent>( onInvoke: (intent) { widget.controller.nextVideo(); return null; }, ),
      PrevVideoIntent: CallbackAction<PrevVideoIntent>( onInvoke: (intent) { widget.controller.prevVideo(); return null; }, ),
    };

    return FocusScope(
      autofocus: true,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: MouseRegion(
              onEnter: (_) => _onPointerActivity(),
              onHover: (_) => _onPointerActivity(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _onUserInteraction,
                onScaleStart: (_) => _pinchStartZoom = widget.controller.videoZoom.value,
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2) return;
                  unawaited(widget.controller.setVideoZoom(_pinchStartZoom * details.scale));
                },
                child: Stack(
                  children: [
                    _buildCenterOverlay(),
                    Positioned(
                      top: 78,
                      left: 12,
                      child: Obx(() => widget.controller.videoZoom.value > 1
                          ? TextButton(
                              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black54),
                              onPressed: () => widget.controller.setVideoZoom(1),
                              child: Text('Zoom ${(widget.controller.videoZoom.value * 100).round()}% · Reset'),
                            )
                          : SizedBox.shrink()),
                    ),
                    
                    // ** Top Bar
                    _buildTopBar(),

                    // ** Bottom Bar
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBottomBar(),
                    ),

                    // ** Total Video Overlay
                    IgnorePointer(
                      ignoring: true,
                      child: FadeTransition(
                        opacity: widget.controller.infoAnimationController,
                        child: Obx(
                          () => widget.controller.infoOverlayText.value.isEmpty
                              ? SizedBox.shrink()
                              : '${widget.controller.infoOverlayText.value}'.text.bold.white.make().pSymmetric(h: 8, v: 4).box.color(Colors.black).make().cornerRadius(90),
                        ),
                      ),
                    ).centered(),

                    // ** Info Overlay
                    Positioned(
                      top: 78,
                      right: 12,
                      child: FadeTransition(
                        opacity: _infoAnimationController,
                        child: _infoText.isEmpty
                            ? SizedBox.shrink()
                            : _infoText.text.bold.size(12).white.make().pSymmetric(h: 12, v: 4).box.color(Colors.black).roundedLg.make().centered(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterOverlay() {
    return Obx(() {
      if (widget.controller.isBuffering.value && widget.controller.isInitialized.value) {
        return Center(child: CircularProgressIndicator.adaptive());
      }

      return SizedBox.shrink();
    });
  }


  Widget _buildTopBar() {
    return Obx(() {
      final video = widget.controller.currentVideo.value;
      final totalPlaylist = widget.controller.playlist.length;
      final currentPlaylistIndex = widget.controller.currentIndexPlaying.value;
      final currentPlaylistNumber = totalPlaylist > 0 ? (currentPlaylistIndex + 1).clamp(1, totalPlaylist) : 0;

      return AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: 100.milliseconds,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 36, 16, 18),
          child: HStack(
            [

              // if ((video.videoCode ?? '').isNotEmpty) ...[
                
              // ],

              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 16, fillColor: Colors.black),
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      totalPlaylist > 0 ? '($currentPlaylistNumber/$totalPlaylist)  •' : '(0/0) •',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ).pOnly(right: 8),

                    Text(
                      video.videoCode!.isNotBlank ? video.videoCode! : 'NON-JAV',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (video.viewCount != null && video.viewCount! > 0)
                      Text(
                        ' • ${video.viewCount} views • ${video.videoPath?.isHasIdSub() == true ? '🇮🇩 ID Sub' : video.videoPath?.isHasEnSub() == true ? '🇬🇧 EN Sub' : 'No Sub' } • ${video.videoPath?.isHasUncensored() == true ? '🎞️ Uncensored' : 'Censored'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: .7),
                        ),
                      ),
                  ],
                ).onTap(() {
                  HelperMisc.copyToClipboard(video.videoCode ?? '', showToast: true);
                }),
              ),

              Spacer(),


              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                child: Icon(UIconsPro.regularRounded.plus, size: 14, color: Colors.white).p8(),
              ).tooltip('Add To Cart (C)').onInkTap(() => widget.controller.addToCart()),

              8.widthBox,

              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                child: Icon(UIconsPro.regularRounded.info, size: 14, color: Colors.white).p8(),
              ).tooltip('Video Info (I)').onInkTap(() => widget.controller.openInfo()),

              8.widthBox,

              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                child: Icon(UIconsPro.regularRounded.list, size: 14, color: Colors.white).p8(),
              ).tooltip('Playlist (L)').onInkTap(() => widget.controller.openList()),

              8.widthBox,

              PopupMenuButton<String>(
                tooltip: 'Subtitles',
                child: Container(
                  decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                  child: Icon(Icons.subtitles_outlined, size: 14, color: Colors.white).p8(),
                ),
                onSelected: (value) async {
                  if (value == 'load') {
                    await widget.controller.pickSubtitle();
                  } else {
                    await widget.controller.selectSubtitle(value == 'no' ? SubtitleTrack.no() : SubtitleTrack.auto());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'load', child: Text('Load subtitle file…')),
                  PopupMenuItem(value: 'auto', child: Text('Auto')),
                  PopupMenuItem(value: 'no', child: Text('Off')),
                ],
              ),

              8.widthBox,

              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
                child: Icon(Icons.picture_in_picture_alt_rounded, size: 14, color: Colors.white).p8(),
              ).tooltip('Mini Player (P)').onInkTap(() async {
                widget.controller.enterMiniMode();
                Get.back();
              }),

              8.widthBox,

              Container(
                decoration: ExDecorator.box(
                  borderColor: Colors.transparent,
                  borderRadius: 12,
                  fillColor: AppColor.black120,
                ),
                child: Icon(UIconsPro.regularRounded.cross_small, size: 14, color: Colors.white).p8(),
              ).tooltip('Close (Q)').onInkTap(() async {
                await widget.controller.stopPlayback();
                Get.back();
              }),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildBottomBar() {
    return Obx(() {
      final video = widget.controller.currentVideo.value;
      final pos = widget.controller.position.value;
      final dur = widget.controller.duration.value;
      final volumeValue = widget.controller.volume.value;
      final speed = widget.controller.playbackSpeed.value;
      final bufferPercent = widget.controller.bufferingPercent.value;
      final hasPrev = widget.controller.currentIndexPlaying.value > 0;
      final hasNext = widget.controller.currentIndexPlaying.value + 1 < widget.controller.playlist.length;
      final isFullscreen = widget.controller.isFullScreen.value;

      return AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: 100.milliseconds,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: .85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showTitle) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        video.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ).tooltip(video.videoPath ?? '').opacity(value: .90),
                    ),
                    
                  ],
                ),
                SizedBox(height: 12),
              ],
              _buildProgressBar(pos, dur, bufferPercent),
              SizedBox(height: 16),
              Row(
                children: [
                  _buildControlIcon(
                    icon: widget.controller.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    tooltip: widget.controller.isPlaying.value ? 'Pause (Space)' : 'Play (Space)',
                    size: 32,
                    onTap: _togglePlayPause,
                  ),
                  SizedBox(width: 8),
                  _buildSecondaryIcon(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Previous (Shift + <)',
                    enabled: hasPrev,
                    onTap: () async {
                      await widget.controller.prevVideo();
                      _showControls();
                    },
                  ),
                  _buildSecondaryIcon(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Next (Shift + >)',
                    enabled: hasNext,
                    onTap: () async {
                      await widget.controller.nextVideo();
                      _showControls();
                    },
                  ),
                  SizedBox(width: 12),
                  Text(
                    '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  _buildVolumeCluster(volumeValue),
                  SizedBox(width: 12),
                  _buildSpeedMenu(speed),
                  SizedBox(width: 12) ,
                  _buildSettingsButton(),
                  SizedBox(width: 12) ,

                  _buildFullscreenButton(isFullscreen),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildProgressBar(Duration pos, Duration dur, double bufferPercent) {
    final maxPosition = math.max(dur.inMilliseconds, 1);
    void requestPreview(double value) {
      final second = (value.clamp(0, math.max(dur.inMilliseconds - 1, 0)) / 1000).floor();
      _seekPreviewSecond = second;
      if (dur > Duration.zero) _seekPreview.request(widget.controller.currentVideo.value.videoPath ?? '', second);
    }
    final sliderValue = (_scrubValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxPosition.toDouble());
    final playedFraction = sliderValue / maxPosition;
    final bufferedFraction = bufferPercent.isNaN ? 0.0 : bufferPercent.clamp(0.0, 100.0) / 100.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final seekWidth = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
        final hasVideoPath = (widget.controller.currentVideo.value.videoPath ?? '').isNotEmpty && dur > Duration.zero;

        double calcValueFromDx(double dx) {
          final ratio = (dx / seekWidth).clamp(0.0, 1.0);
          return ratio * maxPosition;
        }

        void onSeekHover(Offset localPosition) {
          final value = calcValueFromDx(localPosition.dx);
          final dx = localPosition.dx.clamp(0.0, seekWidth);
          _cancelHideTimer();
          if (_isSeekPreviewVisible && (dx - _seekPreviewDx).abs() < 1) return;
          setState(() {
            _isSeekPreviewVisible = true;
            _seekPreviewDx = dx;
            requestPreview(value);
          });
        }

        final previewWidth = 140.0;
        final previewLeft = (_seekPreviewDx - (previewWidth / 2)).clamp(0.0, (seekWidth - previewWidth).clamp(0.0, seekWidth));
        final previewTimestamp = _formatDuration(Duration(seconds: _seekPreviewSecond));

        return MouseRegion(
          onEnter: (event) => onSeekHover(event.localPosition),
          onHover: (event) => onSeekHover(event.localPosition),
          onExit: (_) {
            _seekPreview.clear();
            if (_isSeekPreviewVisible) {
              setState(() => _isSeekPreviewVisible = false);
            }
            if (widget.controller.isPlaying.value) _startHideTimer();
          },
          child: SizedBox(
            height: 32,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                if (_isSeekPreviewVisible && hasVideoPath) ...[
                  Positioned(
                    left: previewLeft,
                    top: -106,
                    child: Container(
                      width: previewWidth,
                      padding: EdgeInsets.all(6),
                      decoration: ExDecorator.box(
                        borderRadius: 8,
                        borderColor: Colors.white24,
                        fillColor: Colors.black.withValues(alpha: .9),
                      ),
                      child: VStack(
                        [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: ListenableBuilder(
                              listenable: _seekPreview,
                              builder: (context, _) {
                                final bytes = _seekPreview.bytes;
                                return SizedBox(
                                  width: previewWidth - 12,
                                  height: 72,
                                  child: _seekPreview.isLoading
                                      ? Center(child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70, semanticsLabel: 'Loading preview'),
                                        ))
                                      : bytes == null
                                      ? Icon(Icons.broken_image_outlined, color: Colors.white54, size: 24)
                                      : Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image_outlined, color: Colors.white54)),
                                );
                              },
                            ),
                          ),
                          previewTimestamp.text.white.size(11).makeCentered().pOnly(top: 4),
                        ],
                      ),
                    ),
                  ),
                ],
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: bufferedFraction.clamp(playedFraction, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: playedFraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Color(0xFFFF0034),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 0,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    min: 0,
                    max: maxPosition.toDouble(),
                    value: sliderValue,
                    onChangeStart: (value) {
                      _cancelHideTimer();
                      setState(() {
                        _isSeekPreviewVisible = true;
                        _seekPreviewDx = (value / maxPosition) * seekWidth;
                        requestPreview(value);
                      });
                    },
                    onChanged: (value) {
                      setState(() {
                        _scrubValue = value;
                        _isSeekPreviewVisible = true;
                        _seekPreviewDx = (value / maxPosition) * seekWidth;
                        requestPreview(value);
                      });
                    },
                    onChangeEnd: (value) async {
                      _seekPreview.clear();
                      setState(() {
                        _scrubValue = null;
                        _isSeekPreviewVisible = false;
                      });
                      await widget.controller.seek(Duration(milliseconds: value.round()));
                      if (!mounted) return;
                      if (widget.controller.isPlaying.value) {
                        _startHideTimer();
                      }
                      final target = widget.controller.position.value;
                      final total = widget.controller.duration.value;
                      _showInfo('${_formatDuration(target)} / ${_formatDuration(total)}');
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlIcon({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    double size = 28,
  }) {
    return IconButton(
      iconSize: size,
      splashRadius: size,
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white),
      onPressed: () {
        onTap();
        _showControls();
      },
    );
  }

  Widget _buildSecondaryIcon({
    required IconData icon,
    required Future<void> Function() onTap,
    required bool enabled,
    String? tooltip,
  }) {
    return IconButton(
      iconSize: 24,
      splashRadius: 26,
      tooltip: tooltip,
      icon: Icon(icon, color: enabled ? Colors.white : Colors.white24),
      onPressed: enabled
          ? () async {
              _cancelHideTimer();
              await onTap();
              _startHideTimer();
            }
          : null,
    );
  }

  Widget _buildVolumeCluster(double volumeValue) {
    final icon = volumeValue == 0
        ? Icons.volume_off
        : volumeValue < 0.5
            ? Icons.volume_down
            : Icons.volume_up;

    final showSlider = _isVolumePointerInside || _isVolumeDragging;

    return MouseRegion(
      onEnter: (_) {
        if (!_isVolumePointerInside) {
          setState(() {
            _isVolumePointerInside = true;
          });
        }
      },
      onExit: (_) {
        if (_isVolumePointerInside) {
          setState(() {
            _isVolumePointerInside = false;
          });
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mute (M)',
            icon: Icon(icon, color: Colors.white),
            splashRadius: 24,
            onPressed: () async {
              _cancelHideTimer();
              await _toggleMute();
              _showControls();
            },
          ),
          ClipRect(
            child: AnimatedSize(
              duration: 200.milliseconds,
              curve: Curves.easeOut,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: showSlider ? 110 : 0,
                child: AnimatedOpacity(
                  duration: 150.milliseconds,
                  curve: Curves.easeOut,
                  opacity: showSlider ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !showSlider,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                      ),
                      child: Slider(
                        min: 0,
                        max: 1,
                        value: volumeValue.clamp(0.0, 1.0),
                        onChangeStart: (_) {
                          _cancelHideTimer();
                          if (!_isVolumeDragging) {
                            setState(() => _isVolumeDragging = true);
                          }
                        },
                        onChanged: (value) async {
                          await widget.controller.setVolumeNormalized(value);
                          setState(() {});
                        },
                        onChangeEnd: (_) {
                          if (_isVolumeDragging) {
                            setState(() {
                              _isVolumeDragging = false;
                            });
                          }
                          if (widget.controller.isPlaying.value) {
                            _startHideTimer();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedMenu(double currentSpeed) {
    const speeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      offset: Offset(0, -8),
      initialValue: currentSpeed,
      color: AppColor.black120,
      onSelected: (value) async {
        await widget.controller.setPlaybackRate(value);
        _showInfo('Speed: ${value.toStringAsFixed(2)}x');
        _showControls();
      },
      itemBuilder: (context) => speeds
          .map(
            (speed) => PopupMenuItem<double>(
              value: speed,
              child: Row(
                children: [
                  if (speed == currentSpeed) Icon(Icons.check, size: 16, color: Colors.white) else SizedBox(width: 16),
                  SizedBox(width: 12),
                  Text(
                    '${speed.toStringAsFixed(2)}x',
                    style: TextStyle(
                      color: speed == currentSpeed ? Colors.white : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ExDecorator.box(
          borderRadius: 16,
          fillColor: Colors.white.withValues(alpha: .1),
          borderColor: Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              '${currentSpeed.toStringAsFixed(2)}x',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVideoAdjustments() async {
    final panel = _adjustmentsPanel;
    if (panel != null) {
      await Overlayment.dismiss(panel);
      return;
    }
    if (Overlayment.count > 0) {
      await Overlayment.dismissLast();
      return;
    }
    final panelFocus = FocusNode();
    _adjustmentsPanel = OverPanel(
      alignment: Alignment.centerRight,
      width: 300,
      color: Colors.black12,
      animation: OverSlideAnimation(
        beginAlignment: Alignment.centerRight,
        reverseDurationMilliseconds: 100,
        durationMilliseconds: 400,
      ),
      actions: OverlayActions(
        onReady: () async {
          if (mounted) panelFocus.requestFocus();
        },
        onClose: (_) async {
          _adjustmentsPanel = null;
          _rebuildAdjustments = null;
          _restoreFocus();
        },
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.comma): _toggleVideoAdjustments,
          const SingleActivator(LogicalKeyboardKey.escape): _toggleVideoAdjustments,
        },
        child: Focus(
          focusNode: panelFocus,
          autofocus: true,
          child: StatefulBuilder(builder: (context, update) {
            _rebuildAdjustments = update;
            return _buildVideoAdjustmentsPopup();
          }),
        ),
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(_adjustmentsPanel!, context: context);
    panelFocus.dispose();
  }

  void _setAdjustmentState(VoidCallback update) {
    if (!mounted) return;
    update();
    _rebuildAdjustments?.call(() {});
  }

  Widget _buildSettingsButton() {
    return IconButton(
      tooltip: 'Video Adjustments (,)',
      splashRadius: 24,
      icon: Icon(Icons.settings, color: Colors.white),
      onPressed: _toggleVideoAdjustments,
    );
  }

  Widget _buildVideoAdjustmentsPopup() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Adjustments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)).expand(),
                
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  tooltip: 'Reset',
                  onPressed: _resetVideoAdjustments,
                ),

                IconButton(
                  icon: const Icon(Icons.bookmark_add, color: Colors.white, size: 18),
                  tooltip: 'Save current as custom',
                  onPressed: _saveCurrentCustomPreset,
                ),

                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  tooltip: 'Close',
                  onPressed: _toggleVideoAdjustments,
                ),

              ],
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_hasSavedCustomPreset) ...[
                    _buildPresetChip('Saved'),
                    6.widthBox,
                  ],
                  for (var i = 0; i < _videoPresetNames.length; i++) ...[
                    _buildPresetChip(_videoPresetNames[i]),
                    if (i != _videoPresetNames.length - 1) 6.widthBox,
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildAdjustmentSlider('Brightness', _brightness, -100, 100, (v) async {
              _setAdjustmentState(() {
                _brightness = v;
                _activeAdjustmentPreset = 'Custom';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('brightness', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Contrast', _contrast, -100, 100, (v) async {
              _setAdjustmentState(() {
                _contrast = v;
                _activeAdjustmentPreset = 'Custom';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('contrast', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Saturation', _saturation, -100, 100, (v) async {
              _setAdjustmentState(() {
                _saturation = v;
                _activeAdjustmentPreset = 'Custom';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('saturation', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Hue', _hue, -180, 180, (v) async {
              _setAdjustmentState(() {
                _hue = v;
                _activeAdjustmentPreset = 'Custom';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('hue', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Gamma', _gamma, -100, 100, (v) async {
              _setAdjustmentState(() {
                _gamma = v;
                _activeAdjustmentPreset = 'Custom';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('gamma', v.toStringAsFixed(0));
            }),

            Divider(color: Colors.white30).pOnly(bottom: 8),

            HStack([
              Obx(
                () => Checkbox.adaptive(
                  value: widget.controller.isAudioNormalizationEnabled.value,
                  onChanged: (value) async {
                    final enabled = value ?? false;
                    await widget.controller.applyAudioNormalization(enabled: enabled);
                    final active = widget.controller.isAudioNormalizationEnabled.value;
                    if (enabled && !active) {
                      _showInfo('Audio normalization unsupported');
                    } else {
                      _showInfo(active ? 'Audio normalization on' : 'Audio normalization off');
                    }
                    _showControls();
                  },
                ),
              ),
              'Audio Normalization'.text.white.size(12).make().pOnly(left: 8).expand(),
            ]),
            Row(
              children: [
                const Text('Rotation', style: TextStyle(color: Colors.white, fontSize: 12)).expand(),
                IconButton(
                  tooltip: 'Rotate left 90°',
                  icon: const Icon(Icons.rotate_left, color: Colors.white, size: 18),
                  onPressed: () => _rotateVideo(clockwise: false),
                ),
                IconButton(
                  tooltip: 'Rotate right 90°',
                  icon: const Icon(Icons.rotate_right, color: Colors.white, size: 18),
                  onPressed: () => _rotateVideo(clockwise: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    const snapRange = 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                color: value == 0 ? Colors.white54 : Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white30,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: (v) {
              // kalau deket 0, langsung snap ke 0
              if (v.abs() < snapRange) {
                v = 0;
              }
              onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _rotateVideo({required bool clockwise}) async {
    final p = widget.controller.player.platform;
    if (p is! NativePlayer) {
      _showInfo('Video rotation unsupported');
      return;
    }
    try {
      await p.command(['cycle-values', 'video-rotate', ...(clockwise ? ['0', '90', '180', '270'] : ['0', '270', '180', '90'])]);
    } catch (_) {
      if (mounted) _showInfo('Failed to rotate video');
    }
  }

  Future<void> _resetVideoAdjustments() async {
    final p = widget.controller.player.platform;
    if (p is NativePlayer) await p.setProperty('video-rotate', '0');
    if (!mounted) return;
    await _applyVideoAdjustments(
      brightness: 0,
      contrast: 0,
      saturation: 0,
      hue: 0,
      gamma: 0,
      presetName: 'Custom',
    );
    _showInfo('Adjustments reset');
  }

  Future<void> _saveCurrentCustomPreset() async {
    AppPref.setPlayerCustomAdjustment({
      'brightness': _brightness,
      'contrast': _contrast,
      'saturation': _saturation,
      'hue': _hue,
      'gamma': _gamma,
    });
    if (!_hasSavedCustomPreset) {
      _setAdjustmentState(() => _hasSavedCustomPreset = true);
    }
    _showInfo('Custom preset saved');
  }

  Widget _buildPresetChip(String name) {
    final isActive = _activeAdjustmentPreset == name;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async => _applyVideoAdjustmentPreset(name),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: ExDecorator.box(
          borderRadius: 999,
          fillColor: isActive ? Colors.white : Colors.white.withValues(alpha: .08),
          borderColor: isActive ? Colors.white : Colors.white24,
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _applyVideoAdjustmentPreset(String preset) async {
    if (preset == 'Saved') {
      final values = AppPref.getPlayerCustomAdjustment();
      if (values.isEmpty) {
        _showInfo('No saved preset');
        return;
      }
      await _applyVideoAdjustments(
        brightness: values['brightness'] ?? 0,
        contrast: values['contrast'] ?? 0,
        saturation: values['saturation'] ?? 0,
        hue: values['hue'] ?? 0,
        gamma: values['gamma'] ?? 0,
        presetName: 'Saved',
      );
      return;
    }

    final values = _videoPresetValues[preset];
    if (values != null) {
      await _applyVideoAdjustments(
        brightness: values['brightness'] ?? 0,
        contrast: values['contrast'] ?? 0,
        saturation: values['saturation'] ?? 0,
        hue: values['hue'] ?? 0,
        gamma: values['gamma'] ?? 0,
        presetName: preset,
      );
      return;
    }

    await _applyVideoAdjustments(
      brightness: 0,
      contrast: 0,
      saturation: 0,
      hue: 0,
      gamma: 0,
      presetName: 'Custom',
    );
  }

  static const Map<String, Map<String, double>> _videoPresetValues = {
    'Cinematic': {
      'brightness': -8,
      'contrast': 18,
      'saturation': -12,
      'hue': 0,
      'gamma': -6,
    },
    'Vivid': {
      'brightness': 4,
      'contrast': 16,
      'saturation': 22,
      'hue': 0,
      'gamma': 6,
    },
    'Noir': {
      'brightness': -6,
      'contrast': 28,
      'saturation': -100,
      'hue': 0,
      'gamma': -4,
    },
    'Warm': {
      'brightness': 2,
      'contrast': 8,
      'saturation': 10,
      'hue': 8,
      'gamma': 2,
    },
    'Cool': {
      'brightness': 0,
      'contrast': 10,
      'saturation': 6,
      'hue': -10,
      'gamma': 1,
    },
    'Soft': {
      'brightness': 6,
      'contrast': -14,
      'saturation': -8,
      'hue': 0,
      'gamma': 10,
    },
    'Punch': {
      'brightness': 1,
      'contrast': 24,
      'saturation': 18,
      'hue': 0,
      'gamma': -2,
    },
    'Night': {
      'brightness': -16,
      'contrast': 12,
      'saturation': -18,
      'hue': 0,
      'gamma': -8,
    },
    'Flat': {
      'brightness': 0,
      'contrast': -22,
      'saturation': -20,
      'hue': 0,
      'gamma': 8,
    },
  };

  Future<void> _applyVideoAdjustments({
    required double brightness,
    required double contrast,
    required double saturation,
    required double hue,
    required double gamma,
    required String presetName,
  }) async {
    _setAdjustmentState(() {
      _brightness = brightness;
      _contrast = contrast;
      _saturation = saturation;
      _hue = hue;
      _gamma = gamma;
      _activeAdjustmentPreset = presetName;
    });

    final p = widget.controller.player.platform;
    if (p is NativePlayer) {
      await p.setProperty('brightness', brightness.toStringAsFixed(0));
      await p.setProperty('contrast', contrast.toStringAsFixed(0));
      await p.setProperty('saturation', saturation.toStringAsFixed(0));
      await p.setProperty('hue', hue.toStringAsFixed(0));
      await p.setProperty('gamma', gamma.toStringAsFixed(0));
    }
    _showInfo('Preset: $presetName');
  }


  Widget _buildFullscreenButton(bool isFullscreen) {
    return IconButton(
      splashRadius: 24,
      tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
      icon: Icon(
        isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        color: Colors.white,
      ),
      onPressed: () async {
        _cancelHideTimer();
        await widget.controller.toggleFullscreen(widget.videoState);
        _startHideTimer();
      },
    );
  }

  void _onUserInteraction() {
    _showControls();
  }

  void _onPointerActivity() {
    _showControls();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isSeekPreviewVisible) return;
    _hideTimer = Timer(_autoHideDuration, () {
      if (!mounted) return;
      _seekPreview.clear();
      setState(() {
        _controlsVisible = false;
        _isSeekPreviewVisible = false;
      });
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _showControls({bool permanent = false}) {
    if (!mounted) return;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _cancelHideTimer();
    if (!permanent && widget.controller.isPlaying.value) {
      _startHideTimer();
    }
    _restoreFocus();
  }

  Future<void> _togglePlayPause() async {
    await widget.controller.togglePlayPause();
    _showControls();
    _showInfo(widget.controller.isPlaying.value ? 'Playing' : 'Paused');
  }

  Future<void> _seekRelative(Duration offset) async {
    await widget.controller.seekRelative(offset);
    final pos = widget.controller.position.value;
    final dur = widget.controller.duration.value;
    final label = offset.isNegative ? 'Backward' : 'Forward';
    _showInfo(
      '$label: ${_formatDuration(pos)} / ${_formatDuration(dur)}',
    );
    _showControls();
  }

  Future<void> _changeVolume(double delta) async {
    await widget.controller.adjustVolume(delta);
    final percent = (widget.controller.volume.value * 100).clamp(0, 100).round();
    _showInfo('Volume: $percent%');
    _showControls();
  }

  Future<void> _changeSpeed(double delta) async {
    await widget.controller.adjustPlaybackRate(delta);
    _showInfo('Speed: ${widget.controller.playbackSpeed.value.toStringAsFixed(2)}x');
    _showControls();
  }

  Future<void> _toggleMute() async {
    if (widget.controller.volume.value == 0.0) {
      final target = (_preMuteVolume ?? 0.5).clamp(0.0, 1.0);
      await widget.controller.setVolumeNormalized(target);
      final percent = (target * 100).round();
      _showInfo('Volume: $percent%');
    } else {
      _preMuteVolume = widget.controller.volume.value;
      await widget.controller.mute();
      _showInfo('Muted');
    }
    _showControls();
  }

  void _handleEqualPress() {
    final now = DateTime.now();
    if (_lastEqualPress != null && now.difference(_lastEqualPress!) <= 400.milliseconds) {
      _lastEqualPress = null;
      _toggleFullscreen();
    } else {
      _lastEqualPress = now;
    }
  }

  Future<void> _toggleFullscreen() async {
    try {
      _cancelHideTimer();
      final willBeFullscreen = !widget.controller.isFullScreen.value;
      await widget.controller.toggleFullscreen(widget.videoState);
      _showInfo(willBeFullscreen ? 'Fullscreen' : 'Windowed');
    } catch (_) {}
  }

  void _showInfo(String text) {
    if (!mounted) return;
    _infoTimer?.cancel();
    setState(() => _infoText = text);
    _infoAnimationController.forward(from: 0);
    _infoTimer = Timer(800.milliseconds, () {
      if (!mounted) return;
      _infoAnimationController.reverse();
    });
  }

  String _formatDuration(Duration duration) {
    final positive = duration < Duration.zero ? Duration.zero : duration;
    final hours = positive.inHours;
    final minutes = positive.inMinutes.remainder(60);
    final seconds = positive.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class PlayPauseIntent extends Intent { const PlayPauseIntent(); }
class SeekForward5sIntent extends Intent { const SeekForward5sIntent(); }
class SeekForward30sIntent extends Intent { const SeekForward30sIntent(); }
class SeekForward60sIntent extends Intent { const SeekForward60sIntent(); }
class SeekBackward5sIntent extends Intent { const SeekBackward5sIntent(); }
class SeekBackward30sIntent extends Intent { const SeekBackward30sIntent(); }
class SeekBackward60sIntent extends Intent { const SeekBackward60sIntent(); }
class VolumeUpIntent extends Intent { const VolumeUpIntent(); }
class VolumeDownIntent extends Intent { const VolumeDownIntent(); }
class SpeedUpIntent extends Intent { const SpeedUpIntent(); }
class SpeedDownIntent extends Intent { const SpeedDownIntent(); }
class MuteIntent extends Intent { const MuteIntent(); }
class EqualTapIntent extends Intent { const EqualTapIntent(); }
class ToggleVideoFitIntent extends Intent { const ToggleVideoFitIntent(); }
class ToggleVideoAdjustmentsIntent extends Intent { const ToggleVideoAdjustmentsIntent(); }
class OpenListIntent extends Intent { const OpenListIntent(); }
class BackIntent extends Intent { const BackIntent(); }
class OpenScreenshotIntent extends Intent { const OpenScreenshotIntent(); }
class OpenInfoIntent extends Intent { const OpenInfoIntent(); }
class AddToCartIntent extends Intent { const AddToCartIntent(); }
class NextVideoIntent extends Intent { const NextVideoIntent(); }
class PrevVideoIntent extends Intent { const PrevVideoIntent(); }
class MiniPlayerIntent extends Intent { const MiniPlayerIntent(); }
