// ignore_for_file: implementation_imports, depend_on_referenced_packages, unawaited_futures, deprecated_member_use

import 'dart:async';

import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/center_seek_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/material_progress_bar.dart';
import 'package:chewie/src/material/widgets/options_dialog.dart';
import 'package:chewie/src/material/widgets/playback_speed_dialog.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/videos_entity.dart';

class ExMaterialControls extends StatefulWidget {
  const ExMaterialControls({
    this.showPlayButton = true,
    required this.video,
    super.key,
  });

  final bool showPlayButton;
  final Videos video;

  @override
  State<StatefulWidget> createState() {
    return _ExMaterialControlsState();
  }
}

class _ExMaterialControlsState extends State<ExMaterialControls> with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  late var _subtitlesPosition = Duration.zero;
  bool _subtitleOn = false;
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;

  final barHeight = 48.0 * 1.5;
  final marginSize = 5.0;

  late VideoPlayerController controller;
  ChewieController? _chewieController;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;

  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
    _focusNode = FocusNode();
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          ) ??
          const Center(child: Icon(Icons.error, color: Colors.white, size: 42));
    }

    return FocusScope(
      autofocus: true,
      child: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            print('Keyboard shortcut pressed: ${event.logicalKey.debugName}');
            if (event.logicalKey == LogicalKeyboardKey.space) {
              _playPause();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _seekForward();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _seekBackward();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _volumeUp();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _volumeDown();
            }
          }
        },
        child: MouseRegion(
          // onHover: (_) {
          //   _focusNode.requestFocus();
          //   _cancelAndRestartTimer();
          // },
          child: GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
              _cancelAndRestartTimer();
            },
            child: AbsorbPointer(
              absorbing: notifier.hideStuff,
              child: Stack(
                children: [
                  if (_displayBufferingIndicator) _chewieController?.bufferingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator()) else _buildHitArea(),
                  _buildActionBar(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (_subtitleOn)
                        Transform.translate(
                          offset: Offset(
                            0.0,
                            notifier.hideStuff ? barHeight * 0.8 : 0.0,
                          ),
                          child: _buildSubtitles(
                            context,
                            chewieController.subtitle!,
                          ),
                        ),
                      _buildBottomBar(context),
                    ],
                  ),
                ],
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
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildActionBar() {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedOpacity(
          opacity: notifier.hideStuff ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Row(
            children: [
              _buildSubtitleToggle(),
              if (chewieController.showOptions) _buildOptionsButton(),
            ],
          ),
        ),
      ),
    );
  }

  List<OptionItem> _buildOptions(BuildContext context) {
    final options = <OptionItem>[
      OptionItem(
        onTap: (context) async {
          Navigator.pop(context);
          _onSpeedButtonTap();
        },
        iconData: Icons.speed,
        title: chewieController.optionsTranslation?.playbackSpeedButtonText ?? 'Playback speed',
      ),
    ];

    if (chewieController.additionalOptions != null && chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }
    return options;
  }

  Widget _buildOptionsButton() {
    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: IconButton(
        onPressed: () async {
          _hideTimer?.cancel();

          if (chewieController.optionsBuilder != null) {
            await chewieController.optionsBuilder!(
              context,
              _buildOptions(context),
            );
          } else {
            await showModalBottomSheet<OptionItem>(
              context: context,
              isScrollControlled: true,
              useRootNavigator: chewieController.useRootNavigator,
              builder: (context) => OptionsDialog(
                options: _buildOptions(context),
                cancelButtonText: chewieController.optionsTranslation?.cancelButtonText,
              ),
            );
          }

          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        },
        icon: const Icon(Icons.more_vert, color: Colors.white),
      ),
    );
  }

  Widget _buildSubtitles(BuildContext context, Subtitles subtitles) {
    if (!_subtitleOn) {
      return const SizedBox();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }

    if (chewieController.subtitleBuilder != null) {
      return chewieController.subtitleBuilder!(
        context,
        currentSubtitle.first!.text,
      );
    }

    return Padding(
      padding: EdgeInsets.all(marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          currentSubtitle.first!.text.toString(),
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: barHeight + (chewieController.isFullScreen ? 10.0 : 0),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: !chewieController.isFullScreen ? 10.0 : 0,
        ),
        child: SafeArea(
          top: false,
          bottom: chewieController.isFullScreen,
          minimum: chewieController.controlsSafeAreaMinimum,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: Row(children: [
                    _buildProgressBar(),
                  ]),
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMuteButton(controller).pOnly(right: 8),
                    _buildPosition(),
                    const Spacer(),
                    if (chewieController.allowFullScreen) _buildExpandButton(),
                    '${widget.video.videoCode}'.text.extraBold.make(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  GestureDetector _buildMuteButton(VideoPlayerController controller) {
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
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight,
          decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
          child: Row(
            children: [
              Icon(
                _latestValue.volume > 0 ? CupertinoIcons.volume_up : CupertinoIcons.volume_off,
                color: Colors.white,
                size: 18,
              ).pOnly(right: 8, bottom: 12),
              'Vol ${(controller.value.volume * 100).toInt()}'.text.size(10).minFontSize(10).make().pOnly(top: 2),

            ],
          ).p8(),
        ),
      ),
    );
  }

  GestureDetector _buildExpandButton() {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 12.0),
          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Center(
            child: Icon(
              chewieController.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;
    final bool showPlayButton = widget.showPlayButton && !_dragging && !notifier.hideStuff;

    return GestureDetector(
      onTap: () {
        if (_latestValue.isPlaying) {
          if (_chewieController?.pauseOnBackgroundTap ?? false) {
            _cancelAndRestartTimer();
          } else {
            if (_displayTapped) {
              setState(() {
                notifier.hideStuff = true;
              });
            } else {
              _cancelAndRestartTimer();
            }
          }
        } else {
          setState(() {
            notifier.hideStuff = true;
          });
        }
      },
      child: Container(
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isFinished && !chewieController.isLive)
              CenterSeekButton(
                iconData: Icons.replay_5,
                backgroundColor: Colors.black54,
                iconColor: Colors.white,
                show: showPlayButton,
                fadeDuration: chewieController.materialSeekButtonFadeDuration,
                iconSize: 16,
                onPressed: () {
                  _seekRelative(const Duration(seconds: -5));
                },
              ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: marginSize),
              child: CenterPlayButton(
                backgroundColor: Colors.black54,
                iconColor: Colors.white,
                isFinished: isFinished,
                isPlaying: controller.value.isPlaying,
                show: showPlayButton,
                onPressed: _playPause,
              ),
            ),
            if (!isFinished && !chewieController.isLive)
              CenterSeekButton(
                iconData: Icons.forward_5,
                backgroundColor: Colors.black54,
                iconColor: Colors.white,
                show: showPlayButton,
                fadeDuration: chewieController.materialSeekButtonFadeDuration,
                iconSize: 16,
                onPressed: () {
                  _seekRelative(const Duration(seconds: 5));
                },
              ),
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
      controller.setPlaybackSpeed(chosenSpeed);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  Widget _buildPosition() {
    final position = _latestValue.position;
    final duration = _latestValue.duration;

    return Container(
      decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: Vx.black.withAlpha(100)),
      child: RichText(
        text: TextSpan(
          text: '${formatDuration(position)} ',
          children: <InlineSpan>[
            TextSpan(
              text: '/ ${formatDuration(duration)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: .75),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ).p8(),
    );
  }

  Widget _buildSubtitleToggle() {
    if (chewieController.subtitle?.isEmpty ?? true) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: _onSubtitleTap,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 12.0, right: 12.0),
        child: Icon(
          _subtitleOn ? Icons.closed_caption : Icons.closed_caption_off_outlined,
          color: _subtitleOn ? Colors.white : Colors.grey[700],
        ),
      ),
    );
  }

  void _onSubtitleTap() {
    setState(() {
      _subtitleOn = !_subtitleOn;
    });
  }

  void _cancelAndRestartTimer() {
    print('Calling _cancelAndRestartTimer, showing controls');
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _subtitleOn = chewieController.showSubtitles && (chewieController.subtitle?.isNotEmpty ?? false);
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;

      chewieController.toggleFullScreen();
      _showAfterExpandCollapseTimer = Timer(
        const Duration(milliseconds: 300),
        () {
          setState(() {
            _cancelAndRestartTimer();
          });
        },
      );
    });
  }

  void _playPause() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      if (isFinished) {
        controller.seekTo(Duration.zero);
      }
      controller.play();
    }

    setState(() {
      print('Playing/Pausing, will force hide controls');
      notifier.hideStuff = true;
    });
  }

  void _seekRelative(Duration relativeSeek) {
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      controller.seekTo(Duration.zero);
    } else if (position > duration) {
      controller.seekTo(duration);
    } else {
      controller.seekTo(position);
    }

    setState(() {
      print('Seeking, will force hide controls');
      notifier.hideStuff = true;
    });
  }

  void _seekBackward() {
    _seekRelative(const Duration(seconds: -5));
  }

  void _seekForward() {
    _seekRelative(const Duration(seconds: 5));
  }

  void _volumeUp() {
    controller.setVolume(_latestValue.volume + 0.1);
    setState(() {});
  }

  void _volumeDown() {
    controller.setVolume(_latestValue.volume - 0.1);
    setState(() {});
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

    final bool buffering = getIsBuffering(controller);

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
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: MaterialVideoProgressBar(
        controller,
        barHeight: 3,
        height: 3,
        onDragStart: () {
          setState(() {
            _dragging = true;
          });

          _hideTimer?.cancel();
        },
        onDragUpdate: () {
          _hideTimer?.cancel();
        },
        onDragEnd: () {
          setState(() {
            _dragging = false;
          });

          _startHideTimer();
        },
        colors: chewieController.materialProgressColors ??
            ChewieProgressColors(
                playedColor: Vx.red600,
                handleColor: Theme.of(context).colorScheme.secondary,
                bufferedColor: Theme.of(context).colorScheme.surface.withValues(alpha: 1),
                backgroundColor: Theme.of(context).disabledColor.withValues(alpha: 1)),
        draggableProgressBar: chewieController.draggableProgressBar,
      ),
    );
  }
}
