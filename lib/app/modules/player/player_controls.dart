import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:overlayment/overlayment.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../core/app_translations.dart';
import '../../utils/helper.dart';
import '../widgets/widget_style.dart';
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
  bool _isMenuOpen = false;

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
  final _seekPreviewLink = LayerLink();
  double _seekWidth = 1;
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
  bool _savingPreset = false;
  String _presetNotice = '';
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
      if (!mounted || _isMenuOpen || Overlayment.count > 0 || ModalRoute.of(context)?.isCurrent == false) return;
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
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft): RotateLeftIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight): RotateRightIntent(),

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
      RotateLeftIntent: CallbackAction<RotateLeftIntent>( onInvoke: (intent) { _rotateVideo(clockwise: false); return null; }, ),
      RotateRightIntent: CallbackAction<RotateRightIntent>( onInvoke: (intent) { _rotateVideo(clockwise: true); return null; }, ),
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
                      top: MediaQuery.sizeOf(context).width < 512 ? 144 : 96,
                      left: 12,
                      child: Obx(() => widget.controller.videoZoom.value > 1
                          ? CupertinoButton(
                              color: Colors.black54,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: const Size(32, 32),
                              onPressed: () => widget.controller.setVideoZoom(1),
                              child: Text('Zoom @{round}% · Reset'.trNamed({'round': '${(widget.controller.videoZoom.value * 100).round()}'})),
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

                    if (_controlsVisible && _isSeekPreviewVisible && (widget.controller.currentVideo.value.videoPath ?? '').isNotEmpty)
                      _buildSeekPreview(),

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
                      top: MediaQuery.sizeOf(context).width < 512 ? 144 : 96,
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
        return const Center(child: CupertinoActivityIndicator(color: Colors.white));
      }

      return SizedBox.shrink();
    });
  }


  Widget _glassPanel(Widget child, {EdgeInsets padding = const EdgeInsets.all(12)}) {
    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark, primaryColor: Colors.white),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E).withValues(alpha: .58),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'CupertinoSystemText', fontSize: 12, color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Obx(() {
      final video = widget.controller.currentVideo.value;
      final total = widget.controller.playlist.length;
      final number = total > 0 ? (widget.controller.currentIndexPlaying.value + 1).clamp(1, total) : 0;
      final code = (video.videoCode ?? '').isNotEmpty ? video.videoCode! : 'NON-JAV';
      final subtitle = video.videoPath?.isHasIdSub() == true ? 'ID Sub'.tr : video.videoPath?.isHasEnSub() == true ? 'EN Sub'.tr : 'No Sub'.tr;
      final details = [if ((video.viewCount ?? 0) > 0) '@{viewCount} views'.trNamed({'viewCount': '${video.viewCount}'}), subtitle,
        video.videoPath?.isHasUncensored() == true ? 'Uncensored'.tr : 'Censored'.tr].join(' · ');
      final metadata = _glassPanel(
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => HelperMisc.copyToClipboard(video.videoCode ?? '', showToast: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$number / $total  ·  $code', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );
      final toolbar = _glassPanel(Row(mainAxisSize: MainAxisSize.min, children: [
        _buildControlIcon(icon: CupertinoIcons.add, size: 16, tooltip: 'Add To Cart (C)'.tr, onTap: widget.controller.addToCart),
        _buildControlIcon(icon: CupertinoIcons.info_circle, size: 16, tooltip: 'Video Info (I)'.tr, onTap: widget.controller.openInfo),
        _buildControlIcon(icon: CupertinoIcons.list_bullet, size: 16, tooltip: 'Playlist (L)'.tr, onTap: widget.controller.openList),
        _buildPlayerMenu(
          tooltip: 'Subtitles'.tr,
          child: const Icon(CupertinoIcons.captions_bubble, color: Colors.white, size: 16),
          items: [('Load subtitle file…'.tr, false), ('Auto'.tr, false), ('Off'.tr, false)],
          onSelected: (index) async {
            if (index == 0) {
              await widget.controller.pickSubtitle();
            } else {
              await widget.controller.selectSubtitle(index == 2 ? SubtitleTrack.no() : SubtitleTrack.auto());
            }
          },
        ),
        _buildControlIcon(icon: CupertinoIcons.rectangle_on_rectangle, size: 16, tooltip: 'Mini Player (P)'.tr, onTap: () {
          widget.controller.enterMiniMode();
          Get.back();
        }),
        _buildControlIcon(icon: CupertinoIcons.xmark, size: 16, tooltip: 'Back (Q)'.tr, onTap: () async {
          await widget.controller.stopPlayback();
          Get.back();
        }),
      ]), padding: const EdgeInsets.all(4));
      return Positioned(
        top: 36, left: 16, right: 16,
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: LayoutBuilder(builder: (context, constraints) => constraints.maxWidth < 480
                ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    SizedBox(width: double.infinity, child: metadata), const SizedBox(height: 8), toolbar,
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Align(alignment: Alignment.topLeft, child: metadata)), const SizedBox(width: 12), toolbar,
                  ])),
          ),
        ),
      );
    });
  }

  Widget _buildBottomBar() {
    return Obx(() {
      final pos = widget.controller.position.value;
      final dur = widget.controller.duration.value;
      final remaining = dur > pos ? dur - pos : Duration.zero;
      final hasPrev = widget.controller.currentIndexPlaying.value > 0;
      final hasNext = widget.controller.currentIndexPlaying.value + 1 < widget.controller.playlist.length;
      final transport = Row(mainAxisSize: MainAxisSize.min, children: [
        _buildSecondaryIcon(icon: CupertinoIcons.backward_end_fill, tooltip: 'Previous (Shift + <)'.tr,
          enabled: hasPrev, onTap: widget.controller.prevVideo),
        const SizedBox(width: 8),
        _buildControlIcon(icon: widget.controller.isPlaying.value ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
          tooltip: widget.controller.isPlaying.value ? 'Pause (Space)'.tr : 'Play (Space)'.tr, onTap: _togglePlayPause),
        const SizedBox(width: 8),
        _buildSecondaryIcon(icon: CupertinoIcons.forward_end_fill, tooltip: 'Next (Shift + >)'.tr,
          enabled: hasNext, onTap: widget.controller.nextVideo),
      ]);
      final volume = _buildVolumeCluster(widget.controller.volume.value);
      final options = Row(mainAxisSize: MainAxisSize.min, children: [
        _buildSpeedMenu(widget.controller.playbackSpeed.value),
        _buildSettingsButton(),
        _buildFullscreenButton(widget.controller.isFullScreen.value),
      ]);
      const timeStyle = TextStyle(color: Colors.white70, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]);
      return IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _glassPanel(LayoutBuilder(builder: (context, constraints) => Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.showTitle) ...[
                    Text(widget.controller.currentVideo.value.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                  ],
                  Row(children: [
                    Text(_formatDuration(pos), style: timeStyle),
                    Expanded(child: _buildProgressBar(pos, dur, widget.controller.bufferingPercent.value)),
                    Text('-${_formatDuration(remaining)}', style: timeStyle),
                  ]),
                  if (constraints.maxWidth < 440) ...[
                    transport,
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [volume, options]),
                  ] else Row(children: [
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: volume)),
                    transport,
                    Expanded(child: Align(alignment: Alignment.centerRight, child: options)),
                  ]),
                ]))),
              ),
            ),
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
    final bufferedFraction = bufferPercent.isNaN ? 0.0 : bufferPercent.clamp(0.0, 100.0) / 100.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final seekWidth = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
        _seekWidth = seekWidth;

        double calcValueFromDx(double dx) {
          final ratio = ((dx - 22) / math.max(seekWidth - 44, 1)).clamp(0.0, 1.0);
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

        return CompositedTransformTarget(
          link: _seekPreviewLink,
          child: MouseRegion(
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
                SizedBox(
                  width: double.infinity,
                  child: _buildCompactSlider(
                    min: 0,
                    max: maxPosition.toDouble(),
                    value: sliderValue,
                    secondaryTrackValue: bufferedFraction * maxPosition,
                    onChangeStart: (value) {
                      _cancelHideTimer();
                      setState(() {
                        _isSeekPreviewVisible = true;
                        _seekPreviewDx = 22 + (value / maxPosition) * math.max(seekWidth - 44, 1);
                        requestPreview(value);
                      });
                    },
                    onChanged: dur == Duration.zero ? null : (value) {
                      setState(() {
                        _scrubValue = value;
                        _isSeekPreviewVisible = true;
                        _seekPreviewDx = 22 + (value / maxPosition) * math.max(seekWidth - 44, 1);
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
          ),
        );
      },
    );
  }

  Widget _buildSeekPreview() {
    const previewWidth = 140.0;
    final previewLeft = (_seekPreviewDx - previewWidth / 2).clamp(0.0, math.max(_seekWidth - previewWidth, 0.0));
    final previewTimestamp = _formatDuration(Duration(seconds: _seekPreviewSecond));
    return Positioned(
      left: 0, top: 0,
      child: IgnorePointer(child: CompositedTransformFollower(
        link: _seekPreviewLink,
        showWhenUnlinked: false,
        offset: Offset(previewLeft.toDouble(), -140),
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
                              child: Semantics(label: 'Loading preview'.tr, child: const CupertinoActivityIndicator(color: Colors.white70)),
                            ))
                          : bytes == null
                          ? Icon(CupertinoIcons.photo, color: Colors.white54, size: AppStyle.largeIconSize)
                          : Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => Icon(CupertinoIcons.photo, color: Colors.white54, size: AppStyle.largeIconSize)),
                    );
                  },
                ),
              ),
              Padding(padding: const EdgeInsets.only(top: 4), child: Center(child: Text(previewTimestamp,
                style: const TextStyle(fontFamily: 'CupertinoSystemText', color: Colors.white, fontSize: 11)))),
            ],
          ),
        ),
      )),
    );
  }

  Widget _buildCompactSlider({
    required double value,
    double? secondaryTrackValue,
    double min = 0,
    double max = 1,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
  }) => SliderTheme(
    data: SliderThemeData(
      trackHeight: 2,
      trackShape: const RectangularSliderTrackShape(),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, disabledThumbRadius: 5, elevation: 0, pressedElevation: 0),
      overlayShape: SliderComponentShape.noOverlay,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      secondaryActiveTrackColor: Colors.white38,
      disabledActiveTrackColor: Colors.white24,
      disabledInactiveTrackColor: Colors.white24,
      thumbColor: Colors.white,
      disabledThumbColor: Colors.white54,
      showValueIndicator: ShowValueIndicator.never,
    ),
    child: Slider(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      value: value, min: min, max: max,
      secondaryTrackValue: secondaryTrackValue,
      onChanged: onChanged, onChangeStart: onChangeStart, onChangeEnd: onChangeEnd,
    ),
  );

  Widget _buildControlIcon({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    double size = AppStyle.playbackIconSize,
  }) => Tooltip(
    message: tooltip ?? '',
    child: CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: Size(size + 16, size + 16),
      onPressed: () { onTap(); _showControls(); },
      child: Icon(icon, size: size, color: Colors.white),
    ),
  );

  Widget _buildSecondaryIcon({
    required IconData icon,
    required Future<void> Function() onTap,
    required bool enabled,
    String? tooltip,
  }) => Tooltip(
    message: tooltip ?? '',
    child: CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(40, 40),
      onPressed: enabled ? () async {
        _cancelHideTimer();
        await onTap();
        if (mounted) _showControls();
      } : null,
      child: Icon(icon, size: 20, color: enabled ? Colors.white : Colors.white24),
    ),
  );

  Widget _buildPlayerMenu({
    required String tooltip,
    required Widget child,
    required List<(String, bool)> items,
    required Future<void> Function(int) onSelected,
  }) => MenuAnchor(
    onOpen: () { _isMenuOpen = true; _cancelHideTimer(); },
    onClose: () { _isMenuOpen = false; _showControls(); },
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.transparent),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    builder: (context, menu, _) => Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(32, 32),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        child: child,
      ),
    ),
    menuChildren: [Builder(builder: (context) => _glassPanel(
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => MenuController.maybeOf(context)?.close()},
        child: SizedBox(width: 180, child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var index = 0; index < items.length; index++) CupertinoButton(
          autofocus: index == 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(32, 32),
          onPressed: () async {
            MenuController.maybeOf(context)?.close();
            await onSelected(index);
            if (mounted) _showControls();
          },
          child: Row(children: [
            SizedBox(width: 20, child: items[index].$2 ? const Icon(CupertinoIcons.check_mark, color: Colors.white, size: 14) : null),
            Expanded(child: Text(items[index].$1, style: const TextStyle(color: Colors.white, fontSize: 12))),
          ]),
        ),
      ]))), padding: const EdgeInsets.all(4),
    ))],
  );

  Widget _buildVolumeCluster(double volumeValue) {
    final icon = volumeValue == 0
        ? CupertinoIcons.speaker_slash_fill
        : volumeValue < 0.5
            ? CupertinoIcons.speaker_1_fill
            : CupertinoIcons.speaker_3_fill;

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
          _buildControlIcon(
            tooltip: 'Mute (M)'.tr, icon: icon, size: 16,
            onTap: () async { _cancelHideTimer(); await _toggleMute(); if (mounted) _showControls(); },
          ),
          ClipRect(
            child: AnimatedSize(
              duration: 200.milliseconds,
              curve: Curves.easeOut,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: showSlider ? 84 : 0,
                child: AnimatedOpacity(
                  duration: 150.milliseconds,
                  curve: Curves.easeOut,
                  opacity: showSlider ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !showSlider,
                    child: _buildCompactSlider(
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
                          if (mounted) setState(() {});
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
        ],
      ),
    );
  }

  Widget _buildSpeedMenu(double currentSpeed) {
    const speeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return _buildPlayerMenu(
      tooltip: 'Playback speed'.tr,
      child: Text('${currentSpeed.toStringAsFixed(2)}×', style: const TextStyle(color: Colors.white, fontSize: 12)),
      items: [for (final speed in speeds) ('${speed.toStringAsFixed(2)}×', speed == currentSpeed)],
      onSelected: (index) async {
        await widget.controller.setPlaybackRate(speeds[index]);
        if (!mounted) return;
        _showInfo('Speed: @{toStringAsFixed}x'.trNamed({'toStringAsFixed': '${speeds[index].toStringAsFixed(2)}'}));
      },
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
      color: Colors.transparent,
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
          const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true, alt: true): () => _rotateVideo(clockwise: false),
          const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true, alt: true): () => _rotateVideo(clockwise: true),
        },
        child: Focus(
          focusNode: panelFocus,
          autofocus: true,
          child: StatefulBuilder(builder: (context, update) {
            _rebuildAdjustments = update;
            return Padding(padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
              child: _glassPanel(_buildVideoAdjustmentsPopup(), padding: EdgeInsets.zero));
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

  Widget _buildSettingsButton() => _buildControlIcon(
    tooltip: 'Video Adjustments (,)'.tr,
    size: 16,
    icon: CupertinoIcons.slider_horizontal_3,
    onTap: _toggleVideoAdjustments,
  );

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
                Text('Adjustments'.tr, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)).expand(),

                _buildControlIcon(icon: CupertinoIcons.arrow_clockwise, size: 16, tooltip: 'Reset'.tr, onTap: _resetVideoAdjustments),

                _buildControlIcon(icon: CupertinoIcons.xmark, size: 16, tooltip: 'Close'.tr, onTap: _toggleVideoAdjustments),

              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final name in _videoPresetNames) _buildPresetChip(name),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(32, 32), color: Colors.white.withValues(alpha: .12),
                onPressed: _savingPreset ? null : _saveCurrentCustomPreset,
                child: Text((_hasSavedCustomPreset ? 'Update preset' : 'Save preset').tr,
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
              )),
              const SizedBox(width: 8),
              Expanded(child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(32, 32), color: Colors.white.withValues(alpha: .12),
                onPressed: !_hasSavedCustomPreset || _savingPreset ? null : () => _applyVideoAdjustmentPreset('Saved'),
                child: Text('Load preset'.tr, style: TextStyle(fontSize: 12,
                  color: _hasSavedCustomPreset ? Colors.white : Colors.white38)),
              )),
            ]),
            if (_presetNotice.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_presetNotice.tr, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
            const SizedBox(height: 16),
            _buildAdjustmentSlider('Brightness'.tr, _brightness, -100, 100, (v) async {
              _setAdjustmentState(() {
                _brightness = v;
                _activeAdjustmentPreset = 'Custom';
                _presetNotice = '';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('brightness', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Contrast'.tr, _contrast, -100, 100, (v) async {
              _setAdjustmentState(() {
                _contrast = v;
                _activeAdjustmentPreset = 'Custom';
                _presetNotice = '';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('contrast', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Saturation'.tr, _saturation, -100, 100, (v) async {
              _setAdjustmentState(() {
                _saturation = v;
                _activeAdjustmentPreset = 'Custom';
                _presetNotice = '';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('saturation', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Hue'.tr, _hue, -180, 180, (v) async {
              _setAdjustmentState(() {
                _hue = v;
                _activeAdjustmentPreset = 'Custom';
                _presetNotice = '';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('hue', v.toStringAsFixed(0));
            }),
            _buildAdjustmentSlider('Gamma'.tr, _gamma, -100, 100, (v) async {
              _setAdjustmentState(() {
                _gamma = v;
                _activeAdjustmentPreset = 'Custom';
                _presetNotice = '';
              });
              final p = widget.controller.player.platform;
              if (p is NativePlayer) await p.setProperty('gamma', v.toStringAsFixed(0));
            }),

            Divider(color: Colors.white30).pOnly(bottom: 8),

            HStack([
              Obx(
                () => CupertinoSwitch(
                  value: widget.controller.isAudioNormalizationEnabled.value,
                  onChanged: (value) async {
                    final enabled = value;
                    await widget.controller.applyAudioNormalization(enabled: enabled);
                    final active = widget.controller.isAudioNormalizationEnabled.value;
                    if (enabled && !active) {
                      _showInfo('Audio normalization unsupported'.tr);
                    } else {
                      _showInfo(active ? 'Audio normalization on'.tr : 'Audio normalization off'.tr);
                    }
                    _showControls();
                  },
                ),
              ),
              'Audio Normalization'.tr.text.white.size(12).make().pOnly(left: 8).expand(),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Rotation'.tr, style: TextStyle(color: Colors.white, fontSize: 12)).expand(),
                _buildControlIcon(icon: CupertinoIcons.rotate_left, size: 16, tooltip: 'Rotate left 90°'.tr, onTap: () => _rotateVideo(clockwise: false)),
                _buildControlIcon(icon: CupertinoIcons.rotate_right, size: 16, tooltip: 'Rotate right 90°'.tr, onTap: () => _rotateVideo(clockwise: true)),
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
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 32,
          child: _buildCompactSlider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: (v) {
              if (v.abs() < snapRange) {
                v = 0;
              }
              onChanged(v);
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _rotateVideo({required bool clockwise}) async {
    final p = widget.controller.player.platform;
    if (p is! NativePlayer) {
      _showInfo('Video rotation unsupported'.tr);
      return;
    }
    try {
      await p.command(['cycle-values', 'video-rotate', ...(clockwise ? ['0', '90', '180', '270'] : ['0', '270', '180', '90'])]);
    } catch (_) {
      if (mounted) _showInfo('Failed to rotate video'.tr);
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
    _showInfo('Adjustments reset'.tr);
  }

  Future<void> _saveCurrentCustomPreset() async {
    _setAdjustmentState(() { _savingPreset = true; _presetNotice = ''; });
    try {
      await AppPref.setPlayerCustomAdjustment({
        'brightness': _brightness,
        'contrast': _contrast,
        'saturation': _saturation,
        'hue': _hue,
        'gamma': _gamma,
      });
      _setAdjustmentState(() {
        _hasSavedCustomPreset = true;
        _activeAdjustmentPreset = 'Saved';
        _presetNotice = 'Custom preset saved';
      });
    } catch (_) {
      _setAdjustmentState(() => _presetNotice = 'Could not save preset. Please retry.');
    } finally {
      _setAdjustmentState(() => _savingPreset = false);
    }
  }

  Widget _buildPresetChip(String name) {
    final isActive = _activeAdjustmentPreset == name;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      minimumSize: const Size(32, 28),
      borderRadius: BorderRadius.circular(999),
      color: isActive ? Colors.white : Colors.white.withValues(alpha: .08),
      onPressed: () => _applyVideoAdjustmentPreset(name),
      child: Text(name.tr, style: TextStyle(color: isActive ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _applyVideoAdjustmentPreset(String preset) async {
    if (preset == 'Saved') {
      final values = AppPref.getPlayerCustomAdjustment();
      if (values.isEmpty) {
        _showInfo('No saved preset'.tr);
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
      _setAdjustmentState(() => _presetNotice = 'Saved preset loaded');
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
      _presetNotice = '';
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
    _showInfo('Preset: @{presetName}'.trNamed({'presetName': '${presetName.tr}'}));
  }


  Widget _buildFullscreenButton(bool isFullscreen) => _buildControlIcon(
    tooltip: isFullscreen ? 'Exit fullscreen'.tr : 'Fullscreen'.tr,
    size: 16,
    icon: isFullscreen ? CupertinoIcons.arrow_down_right_arrow_up_left : CupertinoIcons.arrow_up_left_arrow_down_right,
    onTap: () async {
      _cancelHideTimer();
      await widget.controller.toggleFullscreen(widget.videoState);
      if (mounted) _showControls();
    },
  );

  void _onUserInteraction() {
    if (_controlsVisible) {
      _hideControls();
      _restoreFocus();
    } else {
      _showControls();
    }
  }

  void _onPointerActivity() {
    _showControls();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isSeekPreviewVisible || _isMenuOpen || _isVolumePointerInside || _isVolumeDragging) return;
    _hideTimer = Timer(_autoHideDuration, _hideControls);
  }

  void _hideControls() {
    _cancelHideTimer();
    if (!mounted) return;
    _seekPreview.clear();
    setState(() {
      _controlsVisible = false;
      _isSeekPreviewVisible = false;
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
    _showInfo(widget.controller.isPlaying.value ? 'Playing'.tr : 'Paused'.tr);
  }

  Future<void> _seekRelative(Duration offset) async {
    await widget.controller.seekRelative(offset);
    final pos = widget.controller.position.value;
    final dur = widget.controller.duration.value;
    final label = offset.isNegative ? 'Backward'.tr : 'Forward'.tr;
    _showInfo(
      '$label: ${_formatDuration(pos)} / ${_formatDuration(dur)}',
    );
    _showControls();
  }

  Future<void> _changeVolume(double delta) async {
    await widget.controller.adjustVolume(delta);
    final percent = (widget.controller.volume.value * 100).clamp(0, 100).round();
    _showInfo('Volume: @{percent}%'.trNamed({'percent': '$percent'}));
    _showControls();
  }

  Future<void> _changeSpeed(double delta) async {
    await widget.controller.adjustPlaybackRate(delta);
    _showInfo('Speed: @{toStringAsFixed}x'.trNamed({'toStringAsFixed': '${widget.controller.playbackSpeed.value.toStringAsFixed(2)}'}));
    _showControls();
  }

  Future<void> _toggleMute() async {
    if (widget.controller.volume.value == 0.0) {
      final target = (_preMuteVolume ?? 0.5).clamp(0.0, 1.0);
      await widget.controller.setVolumeNormalized(target);
      final percent = (target * 100).round();
      _showInfo('Volume: @{percent}%'.trNamed({'percent': '$percent'}));
    } else {
      _preMuteVolume = widget.controller.volume.value;
      await widget.controller.mute();
      _showInfo('Muted'.tr);
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
      _showInfo(willBeFullscreen ? 'Fullscreen'.tr : 'Windowed'.tr);
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
class RotateLeftIntent extends Intent { const RotateLeftIntent(); }
class RotateRightIntent extends Intent { const RotateRightIntent(); }
class OpenListIntent extends Intent { const OpenListIntent(); }
class BackIntent extends Intent { const BackIntent(); }
class OpenScreenshotIntent extends Intent { const OpenScreenshotIntent(); }
class OpenInfoIntent extends Intent { const OpenInfoIntent(); }
class AddToCartIntent extends Intent { const AddToCartIntent(); }
class NextVideoIntent extends Intent { const NextVideoIntent(); }
class PrevVideoIntent extends Intent { const PrevVideoIntent(); }
class MiniPlayerIntent extends Intent { const MiniPlayerIntent(); }
