// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';

import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/material_progress_bar.dart';
import 'package:chewie/src/material/widgets/playback_speed_dialog.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';


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

  final barHeight = 54.0 * 1.5;
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
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(context, chewieController.videoPlayerController.value.errorDescription!) ?? Center(child: Icon(Icons.error, color: Colors.white, size: 42));
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
          _showInfoOverlayTemporarily('${videoPlayercontroller.value.isPlaying ? 'Playing' : 'Paused'}');
          return null;
        },
      ),
      SeekForward5sIntent: CallbackAction<SeekForward5sIntent>(
        onInvoke: (intent) {
          _seekForward5s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekForward30sIntent: CallbackAction<SeekForward30sIntent>(
        onInvoke: (intent) {
          _seekForward30s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekForward60sIntent: CallbackAction<SeekForward60sIntent>(
        onInvoke: (intent) {
          _seekForward60s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward5sIntent: CallbackAction<SeekBackward5sIntent>(
        onInvoke: (intent) {
          _seekBackward5s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward30sIntent: CallbackAction<SeekBackward30sIntent>(
        onInvoke: (intent) {
          _seekBackward30s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward60sIntent: CallbackAction<SeekBackward60sIntent>(
        onInvoke: (intent) {
          _seekBackward60s();
          final position = _latestValue.position;
          final duration = _latestValue.duration;
          _showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      VolumeUpIntent: CallbackAction<VolumeUpIntent>(
        onInvoke: (intent) {
          _volumeUp();
          _showInfoOverlayTemporarily('Volume: ${(_latestValue.volume * 100).toInt()}%');
          return null;
        },
      ),
      VolumeDownIntent: CallbackAction<VolumeDownIntent>(
        onInvoke: (intent) {
          _volumeDown();
          _showInfoOverlayTemporarily('Volume: ${(_latestValue.volume * 100).toInt()}%');
          return null;
        },
      ),
      SpeedUpIntent: CallbackAction<SpeedUpIntent>(
        onInvoke: (intent) {
          _speedUp();
          _showInfoOverlayTemporarily('Speed: ${_latestValue.playbackSpeed.toDoubleStringAsFixed(digit: 1)}x');
          return null;
        },
      ),
      SpeedDownIntent: CallbackAction<SpeedDownIntent>(
        onInvoke: (intent) {
          _speedDown();
          _showInfoOverlayTemporarily('Speed: ${_latestValue.playbackSpeed.toDoubleStringAsFixed(digit: 1)}x');
          return null;
        },
      ),
      MuteIntent: CallbackAction<MuteIntent>(
        onInvoke: (intent) {
          _mute();
          _showInfoOverlayTemporarily('Muted');
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
                        FadeTransition(
                          opacity: _infoAnimationController,
                          child: '$_infoOverlayText'.text.bold.make().pSymmetric(h: 8, v: 2).color(Colors.black).cornerRadius(90),
                        ).positioned(bottom: 0),
                      ],

                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildBottomBar(context),
                        ],
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

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: Duration(milliseconds: 300),
      child: Container(
        // color: Colors.purple,
        height: 130, // barHeight + (chewieController.isFullScreen ? 10.0 : 0) + 15,
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          // bottom: !chewieController.isFullScreen ? 10.0 : 0,
        ),
        child: Column(
          // mainAxisSize: MainAxisSize.min,
          // mainAxisAlignment: MainAxisAlignment.center,
          children: [
        
            // video title
            widget.showTitle == false 
              ? 0.heightBox 
              : '${widget.video.title}'.text.maxLines(2).ellipsis.align(TextAlign.center).makeCentered().tooltip('${widget.video.videoPath ?? ''}'),
            
            // progress bar
            _buildProgressBar(),
        
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ** LAYOUT HERE **
                  _buildVolumeButton(videoPlayercontroller),
                  _buildSpeedButton().pOnly(right: 4),
                  _buildPosition(),
                  Spacer(),
                  
                 
        
                  Container(
                    decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: Colors.red.withAlpha(100)),
                    child: HStack(
                      [
                        '${widget.video.videoCode}'.text.extraBold.size(11).minFontSize(11).make().onInkTap(() {
                          HelperMisc.copyToClipboard(widget.video.videoCode, showToast: true);
                        }),
                        '${widget.video.viewCount != null && widget.video.viewCount! > 0 ? '(${widget.video.viewCount} Views)' : ''}'.text.size(11).minFontSize(11).make().pOnly(left: widget.video.videoCode.isNotEmptyAndNotNull ? 8 : 0),
                      ],
                    ).pSymmetric(h: 8, v: 3),
                  ).pOnly(left: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeButton(VideoPlayerController controller) {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: Duration(milliseconds: 300),
        child: Container(
          child: HStack(
            [
              Icon(
                _latestValue.volume == 0 ? CupertinoIcons.volume_off : CupertinoIcons.volume_up,
                color: Colors.white,
                size: 14,
              ).pOnly(right: 8),
              'Vol ${(controller.value.volume * 100).toInt()}'.text.bold.size(11).minFontSize(11).make().pOnly(top: 0),
            ],
          ).pSymmetric(h: 10, v: 3),
        ),
      ),
    );
  }

  Widget _buildPosition() {
    final position = _latestValue.position;
    final duration = _latestValue.duration;

    return Container(
      decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Colors.red.withAlpha(0)),
      child: RichText(
        text: TextSpan(
          text: '${formatDuration(position)} ',
          children: <InlineSpan>[
            TextSpan(
              text: '/ ${formatDuration(duration)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: .75),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
          style: TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ).pSymmetric(h: 8, v: 3),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;

    return GestureDetector(
      onTap: () {
        if (_latestValue.isPlaying && !(_chewieController?.pauseOnBackgroundTap ?? false)) {
          _displayTapped ? setState(() => notifier.hideStuff = true) : _cancelAndRestartTimer();
        } else {
          setState(() => notifier.hideStuff = true);
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

  Future<void> _onSpeedButtonTap() async {
    _hideTimer?.cancel();

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => PlaybackSpeedDialog(
        speeds: chewieController.playbackSpeeds,
        selected: _latestValue.playbackSpeed,
      ),
    );

    if (chosenSpeed != null) {
      await videoPlayercontroller.setPlaybackSpeed(chosenSpeed);
      AppPref.setPlayerSpeed(chosenSpeed);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

 
  Widget _buildSpeedButton() {
    if (chewieController.playbackSpeeds.isEmpty) {
      return SizedBox();
    } else {
      return GestureDetector(
        onTap: _onSpeedButtonTap,
        child: Container(
          height: barHeight,
          color: Colors.transparent,
          padding: EdgeInsets.only(left: 12.0, right: 12.0),
          child: HStack(
            [
              Icon(Icons.speed, color: Colors.white, size: 16).pOnly(right: 8),
              '${_latestValue.playbackSpeed.toDoubleStringAsFixed(digit: 2)}x'.text.size(12).make(),
            ],
          ),
        ),
      );
    }
  }

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

    setState(() {
      // print('Playing/Pausing, will force hide controls');
      notifier.hideStuff = true;
    });
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

    setState(() {
      // print('Seeking, will force hide controls');
      notifier.hideStuff = true;
    });
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
    videoPlayercontroller.setVolume(0.0);
    AppPref.setPlayerVolume(0.0);
    setState(() {});
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

  Widget _buildProgressBar() {
    return Expanded(
      child: MaterialVideoProgressBar(
        videoPlayercontroller,
        barHeight: 3,
        height: 3,
        onDragStart: () => _hideTimer?.cancel(),
        onDragUpdate: () => _hideTimer?.cancel(),
        onDragEnd: () => _startHideTimer(),
        colors: chewieController.materialProgressColors ??
            ChewieProgressColors(
                playedColor: Colors.red,
                handleColor: Colors.red,
                bufferedColor: Theme.of(context).colorScheme.surface.withValues(alpha: 1),
                backgroundColor: Theme.of(context).disabledColor.withValues(alpha: 1)),
        draggableProgressBar: chewieController.draggableProgressBar,
      ),
    );
  }
}
