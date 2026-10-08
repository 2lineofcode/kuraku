// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/material_progress_bar.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../core/app_translations.dart';
import '../../data/models/videos_entity.dart';
import 'widget_style.dart';


// --- Shortcut Intents ---
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
// --- End Shortcut Intents ---

class ExChewieCustom extends StatefulWidget {
  const ExChewieCustom({
    required this.video,
    this.showTitle = true,
    super.key,
  });

  final Videos video;
  final bool? showTitle;

  @override
  State<StatefulWidget> createState() {
    return _ExChewieCustomState();
  }
}

class _ExChewieCustomState extends State<ExChewieCustom> with SingleTickerProviderStateMixin {

  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;

  double? _latestVolume;
  bool _isVolumeHovered = false;
  bool _isVolumeDragging = false;
  bool _isSpeedMenuOpen = false;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;

  bool _showInfoOverlay = false;
  Timer? _infoOverlayTimer;
  late AnimationController _infoAnimationController;
  String _infoOverlayText = '';

  final marginSize = 5.0;

  late VideoPlayerController videoPlayercontroller;
  ChewieController? _chewieController;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;

  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
    _focusNode = FocusNode();
    _infoAnimationController = AnimationController(vsync: this, duration: Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(context, chewieController.videoPlayerController.value.errorDescription!) ?? Center(child: Icon(CupertinoIcons.exclamationmark_circle_fill, color: Colors.white, size: AppStyle.emptyIconSize));
    }

    // --- Shortcuts Map ---
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.space): PlayPauseIntent(),
      // Seek Forward: Arrow Right
      LogicalKeySet(LogicalKeyboardKey.arrowRight): SeekForward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight): SeekForward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowRight): SeekForward60sIntent(),
      // Seek Backward: Arrow Left
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): SeekBackward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft): SeekBackward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowLeft): SeekBackward60sIntent(),
      // Volume: Arrow Up/Down
      LogicalKeySet(LogicalKeyboardKey.arrowUp): VolumeUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowDown): VolumeDownIntent(),
      // Speed: Bracket Left/Right
      LogicalKeySet(LogicalKeyboardKey.bracketLeft): SpeedDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.bracketRight): SpeedUpIntent(),
      // Mute: M
      LogicalKeySet(LogicalKeyboardKey.keyM): MuteIntent(),
    };
    // --- End Shortcuts Map ---

    // --- Actions Map Shortcuts ---
    final actions = <Type, Action<Intent>>{
      PlayPauseIntent: CallbackAction<PlayPauseIntent>(
        onInvoke: (intent) {
          _playPause();
          _showInfoOverlayTemporarily('${videoPlayercontroller.value.isPlaying ? 'Playing'.tr : 'Paused'.tr}');
          return null;
        },
      ),
      SeekForward5sIntent: CallbackAction<SeekForward5sIntent>(
        onInvoke: (intent) {
          _seekForward5s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      SeekForward30sIntent: CallbackAction<SeekForward30sIntent>(
        onInvoke: (intent) {
          _seekForward30s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      SeekForward60sIntent: CallbackAction<SeekForward60sIntent>(
        onInvoke: (intent) {
          _seekForward60s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      SeekBackward5sIntent: CallbackAction<SeekBackward5sIntent>(
        onInvoke: (intent) {
          _seekBackward5s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      SeekBackward30sIntent: CallbackAction<SeekBackward30sIntent>(
        onInvoke: (intent) {
          _seekBackward30s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      SeekBackward60sIntent: CallbackAction<SeekBackward60sIntent>(
        onInvoke: (intent) {
          _seekBackward60s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: @{position} / @{duration}'.trNamed({'position': '${formatDuration(position)}', 'duration': '${formatDuration(duration)}'}));
          return null;
        },
      ),
      VolumeUpIntent: CallbackAction<VolumeUpIntent>(
        onInvoke: (intent) {
          _volumeUp();
          _showInfoOverlayTemporarily('Volume: @{toInt}%'.trNamed({'toInt': '${(_latestValue.volume * 100).toInt()}'}));
          return null;
        },
      ),
      VolumeDownIntent: CallbackAction<VolumeDownIntent>(
        onInvoke: (intent) {
          _volumeDown();
          _showInfoOverlayTemporarily('Volume: @{toInt}%'.trNamed({'toInt': '${(_latestValue.volume * 100).toInt()}'}));
          return null;
        },
      ),
      SpeedUpIntent: CallbackAction<SpeedUpIntent>(
        onInvoke: (intent) {
          _speedUp();
          _showInfoOverlayTemporarily('Speed: @{digit}x'.trNamed({'digit': '${_latestValue.playbackSpeed.toDoubleStringAsFixed(digit: 1)}'}));
          return null;
        },
      ),
      SpeedDownIntent: CallbackAction<SpeedDownIntent>(
        onInvoke: (intent) {
          _speedDown();
          _showInfoOverlayTemporarily('Speed: @{digit}x'.trNamed({'digit': '${_latestValue.playbackSpeed.toDoubleStringAsFixed(digit: 1)}'}));
          return null;
        },
      ),
      MuteIntent: CallbackAction<MuteIntent>(
        onInvoke: (intent) {
          _mute();
          _showInfoOverlayTemporarily('Muted'.tr);
          return null;
        },
      ),
    };
    // --- End Actions Map ---

    return FocusScope(
      autofocus: true,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onFocusChange: (hasFocus) {},
            child: MouseRegion(
              child: GestureDetector(
                onTap: () {
                  _focusNode.requestFocus();
                  _cancelAndRestartTimer();
                },
                child: AbsorbPointer(
                  absorbing: notifier.hideStuff,
                  child: Stack(
                    children: [

                      if (_displayBufferingIndicator) ...[
                        _chewieController?.bufferingBuilder?.call(context) ?? Center(child: CircularProgressIndicator()),
                      ] else ...[
                        _buildHitArea(),
                      ],


                      if (_showInfoOverlay) ...[
                        Center(child: IgnorePointer(child: FadeTransition(
                          opacity: _infoAnimationController,
                          child: _glassPanel(Text(_infoOverlayText)),
                        ))),
                      ],

                      Positioned(
                        left: 0, right: 0, bottom: 0,
                        child: _buildBottomBar(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    _focusNode.dispose();
    _infoOverlayTimer?.cancel();
    _infoAnimationController.dispose();
    super.dispose();
  }

  void _dispose() {
    videoPlayercontroller.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    videoPlayercontroller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _glassPanel(Widget child) => CupertinoTheme(
    data: const CupertinoThemeData(brightness: Brightness.dark, primaryColor: Colors.white),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(12),
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

  Widget _buildControlIcon({required IconData icon, required String tooltip, required VoidCallback onTap, double size = 16}) => Tooltip(
    message: tooltip,
    child: CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: Size(size + 16, size + 16),
      onPressed: () { _cancelAndRestartTimer(); onTap(); },
      child: Icon(icon, color: Colors.white, size: size),
    ),
  );

  Widget _buildBottomBar(BuildContext context) {
    final position = _latestValue.position;
    final duration = _latestValue.duration;
    final remaining = duration > position ? duration - position : Duration.zero;
    final transport = Row(mainAxisSize: MainAxisSize.min, children: [
      _buildControlIcon(icon: CupertinoIcons.gobackward, tooltip: '${'Backward'.tr} 5s', onTap: _seekBackward5s, size: 20),
      const SizedBox(width: 8),
      _buildControlIcon(icon: _latestValue.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
        tooltip: _latestValue.isPlaying ? 'Pause (Space)'.tr : 'Play (Space)'.tr, onTap: _playPause, size: AppStyle.playbackIconSize),
      const SizedBox(width: 8),
      _buildControlIcon(icon: CupertinoIcons.goforward, tooltip: '${'Forward'.tr} 5s', onTap: _seekForward5s, size: 20),
    ]);
    const timeStyle = TextStyle(color: Colors.white70, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]);
    return IgnorePointer(
      ignoring: notifier.hideStuff,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(alignment: Alignment.bottomCenter, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _glassPanel(LayoutBuilder(builder: (context, constraints) {
              final volume = _buildVolumeButton(videoPlayercontroller);
              final speed = _buildSpeedButton();
              return Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.showTitle != false) ...[
                  Text(widget.video.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                ],
                Row(children: [
                  Text(formatDuration(position), style: timeStyle),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildProgressBar())),
                  Text('-${formatDuration(remaining)}', style: timeStyle),
                ]),
                if (constraints.maxWidth < 440) ...[
                  transport,
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [volume, speed]),
                ] else Row(children: [
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: volume)),
                  transport,
                  Expanded(child: Align(alignment: Alignment.centerRight, child: speed)),
                ]),
              ]);
            })),
          )),
        ),
      ),
    );
  }

  Widget _buildVolumeButton(VideoPlayerController controller) => MouseRegion(
    onEnter: (_) { _hideTimer?.cancel(); setState(() => _isVolumeHovered = true); },
    onExit: (_) { setState(() => _isVolumeHovered = false); _startHideTimer(); },
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _buildControlIcon(
        icon: _latestValue.volume == 0 ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_3_fill,
        tooltip: 'Mute (M)'.tr,
        onTap: _mute,
      ),
      ClipRect(child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: SizedBox(width: _isVolumeHovered || _isVolumeDragging ? 84 : 0, child: CupertinoSlider(
          value: _latestValue.volume.clamp(0.0, 1.0),
          activeColor: Colors.white,
          thumbColor: Colors.white,
          onChangeStart: (_) { _hideTimer?.cancel(); setState(() => _isVolumeDragging = true); },
          onChanged: (value) { controller.setVolume(value); AppPref.setPlayerVolume(value); },
          onChangeEnd: (_) { setState(() => _isVolumeDragging = false); _startHideTimer(); },
        )),
      )),
    ]),
  );

  Widget _buildHitArea() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;

    return GestureDetector(
      onTap: () {
        if (_latestValue.isPlaying && !(_chewieController?.pauseOnBackgroundTap ?? false)) {
          _displayTapped ? setState(() => notifier.hideStuff = true) : _cancelAndRestartTimer();
        } else {
          _cancelAndRestartTimer();
        }
      },
      child: Container(
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isFinished) ...[
              Container(
                margin: EdgeInsets.symmetric(horizontal: marginSize),
                child: CenterPlayButton(
                  backgroundColor: AppColor.black120,
                  iconColor: Colors.white,
                  isFinished: isFinished,
                  isPlaying: videoPlayercontroller.value.isPlaying,
                  show: true,
                  onPressed: _playPause,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedButton() => MenuAnchor(
    onOpen: () { _isSpeedMenuOpen = true; _hideTimer?.cancel(); },
    onClose: () {
      if (!mounted) return;
      _isSpeedMenuOpen = false;
      _cancelAndRestartTimer();
      _focusNode.requestFocus();
    },
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.transparent),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    builder: (context, menu, _) => Tooltip(
      message: 'Playback speed'.tr,
      child: CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(32, 32),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        child: Text('${_latestValue.playbackSpeed.toStringAsFixed(2)}×', style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    ),
    menuChildren: [Builder(builder: (context) => _glassPanel(
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => MenuController.maybeOf(context)?.close()},
        child: SizedBox(width: 140, child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final speed in chewieController.playbackSpeeds) CupertinoButton(
            autofocus: speed == chewieController.playbackSpeeds.first,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(32, 32),
            onPressed: () async {
              MenuController.maybeOf(context)?.close();
              await videoPlayercontroller.setPlaybackSpeed(speed);
              AppPref.setPlayerSpeed(speed);
              if (mounted) _focusNode.requestFocus();
            },
            child: Row(children: [
              SizedBox(width: 20, child: speed == _latestValue.playbackSpeed
                ? const Icon(CupertinoIcons.check_mark, color: Colors.white, size: 14) : null),
              Text('${speed.toStringAsFixed(2)}×', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ])),
      ),
    ))],
  );

  void _cancelAndRestartTimer() {
    // print('Calling _cancelAndRestartTimer, showing controls');
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    videoPlayercontroller.addListener(_updateState);

    _updateState();

    if (videoPlayercontroller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _playPause() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;

    if (videoPlayercontroller.value.isPlaying) {
      videoPlayercontroller.pause();
    } else {
      if (isFinished) {
        videoPlayercontroller.seekTo(Duration.zero);
      }
      videoPlayercontroller.play();
    }

    _cancelAndRestartTimer();
  }

  void _seekRelative(Duration relativeSeek) {
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      videoPlayercontroller.seekTo(Duration.zero);
    } else if (position > duration) {
      videoPlayercontroller.seekTo(duration);
    } else {
      videoPlayercontroller.seekTo(position);
    }

    _cancelAndRestartTimer();
  }

  void _seekForward5s() {
    _seekRelative(Duration(seconds: 5));
  }

  void _seekForward30s() {
    _seekRelative(Duration(seconds: 30));
  }

  void _seekForward60s() {
    _seekRelative(Duration(seconds: 60));
  }

  void _seekBackward5s() {
    _seekRelative(Duration(seconds: -5));
  }

  void _seekBackward30s() {
    _seekRelative(Duration(seconds: -30));
  }

  void _seekBackward60s() {
    _seekRelative(Duration(seconds: -60));
  }

  void _volumeUp() {
    videoPlayercontroller.setVolume(_latestValue.volume + 0.05);
    AppPref.setPlayerVolume(_latestValue.volume);
    setState(() {});
  }

  void _volumeDown() {
    videoPlayercontroller.setVolume(_latestValue.volume - 0.05);
    AppPref.setPlayerVolume(_latestValue.volume);
    setState(() {});
  }

  void _speedUp() {
    videoPlayercontroller.setPlaybackSpeed(_latestValue.playbackSpeed + 0.1);
    AppPref.setPlayerSpeed(_latestValue.playbackSpeed);
    setState(() {});
  }

  void _speedDown() {
    videoPlayercontroller.setPlaybackSpeed(_latestValue.playbackSpeed - 0.1);
    AppPref.setPlayerSpeed(_latestValue.playbackSpeed);
    setState(() {});
  }

  void _mute() {
    final volume = _latestValue.volume == 0 ? _latestVolume ?? 0.5 : 0.0;
    if (_latestValue.volume > 0) _latestVolume = _latestValue.volume;
    videoPlayercontroller.setVolume(volume);
    AppPref.setPlayerVolume(volume);
    _cancelAndRestartTimer();
  }

  void _showInfoOverlayTemporarily(String text) {
    _infoOverlayTimer?.cancel();

    setState(() {
      _infoOverlayText = text;
      _showInfoOverlay = true;
    });

    _infoAnimationController.forward();

    _infoOverlayTimer = Timer(Duration(milliseconds: 800), () {
      if (mounted) {
        _infoAnimationController.reverse().then((_) {
          setState(() {
            _showInfoOverlay = false;
            _infoOverlayText = '';
          });
        });
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_latestValue.isPlaying || _isSpeedMenuOpen || _isVolumeHovered || _isVolumeDragging) return;
    final hideControlsTimer = chewieController.hideControlsTimer.isNegative ? ChewieController.defaultHideControlsTimer : chewieController.hideControlsTimer;
    _hideTimer?.cancel();
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final bool buffering = getIsBuffering(videoPlayercontroller);

    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    setState(() {
      _latestValue = videoPlayercontroller.value;
    });
  }

  Widget _buildProgressBar() => SizedBox(
    height: 24,
    child: MaterialVideoProgressBar(
      videoPlayercontroller,
      barHeight: 2,
      handleHeight: 5,
      onDragStart: () => _hideTimer?.cancel(),
      onDragUpdate: () => _hideTimer?.cancel(),
      onDragEnd: () => _startHideTimer(),
      colors: ChewieProgressColors(
        playedColor: Colors.white,
        handleColor: Colors.white,
        bufferedColor: Colors.white38,
        backgroundColor: Colors.white24,
      ),
      draggableProgressBar: chewieController.draggableProgressBar,
    ),
  );
}
