// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';

import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/center_seek_button.dart';
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
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_color.dart';
import '../../core/app_logging.dart';
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


class ChiwieCustomController extends GetxController with StateMixin, GetSingleTickerProviderStateMixin{
  // Player notifier (originally provided via Provider). Now retrieved via Get.find.
  PlayerNotifier? notifier;

  // Video controllers (chewie + video_player)
  ChewieController? _chewieController;
  ChewieController? get chewieController => _chewieController;

  late VideoPlayerController vpcontroller;

  // Reactive state (replaces _latestValue, booleans, etc)
  final latestValue = Rxn<VideoPlayerValue>();
  final latestVolume = RxnDouble();
  final dragging = false.obs;
  final displayTapped = false.obs;
  final displayBufferingIndicator = false.obs;
  final showInfoOverlay = false.obs;
  final infoOverlayText = ''.obs;

  // Timers (keep as nullable, same semantics)
  Timer? hideTimer;
  Timer? initTimer;
  Timer? showAfterExpandCollapseTimer;
  Timer? bufferingDisplayTimer;
  Timer? infoOverlayTimer;

  // Misc
  final barHeight = 54.0 * 1.5;
  final marginSize = 5.0;

  // Animation for info overlay
  late AnimationController infoAnimationController;
  late Animation<double> infoAnimation;

  // FocusNode moved into controller
  final focusNode = FocusNode().obs;

  @override
  void onInit() {
    super.onInit();

    focusNode.value = FocusNode();

    infoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    infoAnimation = infoAnimationController.drive(CurveTween(curve: Curves.easeInOut));

    change(null, status: RxStatus.success());
  }

  void requestFocus(BuildContext context) {
    if (!focusNode.value.hasFocus) {
      FocusScope.of(context).requestFocus(focusNode.value);
    }
  }


  /// Called from the view's build to attach BuildContext and perform didChangeDependencies-like behavior.
  /// This is idempotent — if chewieController changes, it'll reinitialize.
  void attachBuildContext(BuildContext context, Videos video, {bool force = false}) {
    // Get notifier via GetX (full GetX). Make sure PlayerNotifier is registered with Get.put() somewhere.
    notifier ??= Get.find<PlayerNotifier>();

    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);

    if (oldController != _chewieController || force) {
      _disposeInternal();
      // set underlying video player controller reference
      vpcontroller = chewieController!.videoPlayerController;
      _initialize();
    }
  }

  void _disposeInternal() {
    try {
      vpcontroller.removeListener(_updateState);
    } catch (_) {}
    hideTimer?.cancel();
    initTimer?.cancel();
    showAfterExpandCollapseTimer?.cancel();
    bufferingDisplayTimer?.cancel();
  }

  Future<void> _initialize() async {
    // attach listener
    vpcontroller.addListener(_updateState);

    // immediate state update
    _updateState();

    if (vpcontroller.value.isPlaying || (chewieController?.autoPlay ?? false)) {
      _startHideTimer();
    }

    if (chewieController?.showControlsOnInitialize ?? false) {
      initTimer = Timer(const Duration(milliseconds: 200), () {
        notifier?.hideStuff = false;
      });
    }
    update();
  }

  // ------------ UI action methods (converted from original) ------------

  void _cancelAndRestartTimer() {
    hideTimer?.cancel();
    _startHideTimer();

    notifier?.hideStuff = false;
    displayTapped.value = true;
    update();
  }

  void _playPause() {
    final bool isFinished = (latestValue.value?.position ?? Duration.zero) >= (latestValue.value?.duration ?? Duration.zero) && (latestValue.value?.duration.inSeconds ?? 0) > 0;

    if (vpcontroller.value.isPlaying) {
      vpcontroller.pause();
    } else {
      if (isFinished) {
        vpcontroller.seekTo(Duration.zero);
      }
      vpcontroller.play();
    }

    // same semantics as original: force hide controls
    notifier?.hideStuff = true;
  }

  void _seekRelative(Duration relativeSeek) {
    final position = (latestValue.value?.position ?? Duration.zero) + relativeSeek;
    final duration = latestValue.value?.duration ?? Duration.zero;

    if (position < Duration.zero) {
      vpcontroller.seekTo(Duration.zero);
    } else if (position > duration) {
      vpcontroller.seekTo(duration);
    } else {
      vpcontroller.seekTo(position);
    }

    notifier?.hideStuff = true;
  }

  void _seekForward5s() => _seekRelative(const Duration(seconds: 5));
  void _seekForward30s() => _seekRelative(const Duration(seconds: 30));
  void _seekForward60s() => _seekRelative(const Duration(seconds: 60));
  void _seekBackward5s() => _seekRelative(const Duration(seconds: -5));
  void _seekBackward30s() => _seekRelative(const Duration(seconds: -30));
  void _seekBackward60s() => _seekRelative(const Duration(seconds: -60));

  void _volumeUp() {
    vpcontroller.setVolume((latestValue.value?.volume ?? 0.0) + 0.05);
    AppPref.setPlayerVolume(latestValue.value?.volume ?? 0.0);
    // trigger UI update by writing latestValue (listener will update soon)
  }

  void _volumeDown() {
    vpcontroller.setVolume((latestValue.value?.volume ?? 0.0) - 0.05);
    AppPref.setPlayerVolume(latestValue.value?.volume ?? 0.0);
  }

  void _speedUp() {
    vpcontroller.setPlaybackSpeed((latestValue.value?.playbackSpeed ?? 1.0) + 0.1);
    AppPref.setPlayerSpeed(latestValue.value?.playbackSpeed ?? 1.0);
  }

  void _speedDown() {
    vpcontroller.setPlaybackSpeed((latestValue.value?.playbackSpeed ?? 1.0) - 0.1);
    AppPref.setPlayerSpeed(latestValue.value?.playbackSpeed ?? 1.0);
  }

  void _mute() {
    vpcontroller.setVolume(0.0);
    AppPref.setPlayerVolume(0.0);
  }

  void _showInfoOverlayTemporarily(String text) {
    infoOverlayTimer?.cancel();

    infoOverlayText.value = text;
    showInfoOverlay.value = true;

    infoAnimationController.forward();

    infoOverlayTimer = Timer(const Duration(milliseconds: 500), () {
      infoAnimationController.reverse().then((_) {
        showInfoOverlay.value = false;
        infoOverlayText.value = '';
      });
    });
  }

  void _startHideTimer() {
    // final hideControlsTimer = (chewieController?.hideControlsTimer.isNegative ?? true) ? ChewieController.defaultHideControlsTimer : chewieController!.hideControlsTimer;
    final hideControlsTimer = 1.seconds;
    AppLog.logD('hideControlsTimer -> $hideControlsTimer');
    hideTimer?.cancel();
    hideTimer = Timer(hideControlsTimer, () {
      notifier?.hideStuff = true;
    });
  }

  void _bufferingTimerTimeout() {
    displayBufferingIndicator.value = true;
  }

  // Listener called by VideoPlayerController
  void _updateState() {
    final bool buffering = getIsBuffering(vpcontroller);

    if (chewieController?.progressIndicatorDelay != null) {
      if (buffering) {
        bufferingDisplayTimer ??= Timer(chewieController!.progressIndicatorDelay!, _bufferingTimerTimeout);
      } else {
        bufferingDisplayTimer?.cancel();
        bufferingDisplayTimer = null;
        displayBufferingIndicator.value = false;
      }
    } else {
      displayBufferingIndicator.value = buffering;
    }

    latestValue.value = vpcontroller.value;
  }

  // Progress bar callbacks
  void onDragStartProgress() {
    dragging.value = true;
    hideTimer?.cancel();
  }

  void onDragUpdateProgress() {
    hideTimer?.cancel();
  }

  void onDragEndProgress() {
    dragging.value = false;
    _startHideTimer();
  }

  // speed selection bottom sheet
  Future<void> onSpeedButtonTap(BuildContext context) async {
    hideTimer?.cancel();

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: chewieController?.useRootNavigator ?? false,
      builder: (context) => PlaybackSpeedDialog(
        speeds: chewieController?.playbackSpeeds ?? const [],
        selected: latestValue.value?.playbackSpeed ?? 1.0,
      ),
    );

    if (chosenSpeed != null) {
      await vpcontroller.setPlaybackSpeed(chosenSpeed);
      AppPref.setPlayerSpeed(chosenSpeed);
    }

    if (latestValue.value?.isPlaying ?? false) {
      _startHideTimer();
    }
  }


  @override
  void onClose() {
    _disposeInternal();
    infoOverlayTimer?.cancel();
    infoAnimationController.dispose();
    focusNode.value.dispose();
    super.onClose();
  }
}

class WidgetChiwieCustom extends StatelessWidget {
  const WidgetChiwieCustom({
    super.key,
    required this.video,
    this.showPlayButton = true,
  });

  final bool showPlayButton;
  final Videos video;

  @override
  Widget build(BuildContext context) {

    Get.put(PlayerNotifier.init());
    final controller = Get.put<ChiwieCustomController>(ChiwieCustomController());

    controller.attachBuildContext(context, video);


    // Shortcuts map (kept same)
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.space): const PlayPauseIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowRight): const SeekForward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight): const SeekForward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowRight): const SeekForward60sIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowLeft): const SeekBackward5sIntent(),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft): const SeekBackward30sIntent(),
      LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowLeft): const SeekBackward60sIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): const VolumeUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowDown): const VolumeDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.bracketLeft): const SpeedDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.bracketRight): const SpeedUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyM): const MuteIntent(),
    };

    // Actions map (wraps controller methods)
    final actions = <Type, Action<Intent>>{
      PlayPauseIntent: CallbackAction<PlayPauseIntent>(
        onInvoke: (intent) {
          controller._playPause();
          controller._showInfoOverlayTemporarily('${controller.vpcontroller.value.isPlaying ? 'Playing' : 'Paused'}');
          return null;
        },
      ),
      SeekForward5sIntent: CallbackAction<SeekForward5sIntent>(
        onInvoke: (intent) {
          controller._seekForward5s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekForward30sIntent: CallbackAction<SeekForward30sIntent>(
        onInvoke: (intent) {
          controller._seekForward30s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekForward60sIntent: CallbackAction<SeekForward60sIntent>(
        onInvoke: (intent) {
          controller._seekForward60s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Forward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward5sIntent: CallbackAction<SeekBackward5sIntent>(
        onInvoke: (intent) {
          controller._seekBackward5s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward30sIntent: CallbackAction<SeekBackward30sIntent>(
        onInvoke: (intent) {
          controller._seekBackward30s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      SeekBackward60sIntent: CallbackAction<SeekBackward60sIntent>(
        onInvoke: (intent) {
          controller._seekBackward60s();
          final position = controller.latestValue.value?.position ?? Duration.zero;
          final duration = controller.latestValue.value?.duration ?? Duration.zero;
          controller._showInfoOverlayTemporarily('Backward: ${formatDuration(position)} / ${formatDuration(duration)}');
          return null;
        },
      ),
      VolumeUpIntent: CallbackAction<VolumeUpIntent>(
        onInvoke: (intent) {
          controller._volumeUp();
          controller._showInfoOverlayTemporarily('Volume: ${((controller.latestValue.value?.volume ?? 0.0) * 100).toInt()}%');
          return null;
        },
      ),
      VolumeDownIntent: CallbackAction<VolumeDownIntent>(
        onInvoke: (intent) {
          controller._volumeDown();
          controller._showInfoOverlayTemporarily('Volume: ${((controller.latestValue.value?.volume ?? 0.0) * 100).toInt()}%');
          return null;
        },
      ),
      SpeedUpIntent: CallbackAction<SpeedUpIntent>(
        onInvoke: (intent) {
          controller._speedUp();
          controller._showInfoOverlayTemporarily('Speed: ${(controller.latestValue.value?.playbackSpeed ?? 1.0).toDoubleStringAsFixed(digit: 1)}x');
          return null;
        },
      ),
      SpeedDownIntent: CallbackAction<SpeedDownIntent>(
        onInvoke: (intent) {
          controller._speedDown();
          controller._showInfoOverlayTemporarily('Speed: ${(controller.latestValue.value?.playbackSpeed ?? 1.0).toDoubleStringAsFixed(digit: 1)}x');
          return null;
        },
      ),
      MuteIntent: CallbackAction<MuteIntent>(
        onInvoke: (intent) {
          controller._mute();
          controller._showInfoOverlayTemporarily('Muted');
          return null;
        },
      ),
    };

    // Build UI
    return FocusScope(
      autofocus: true,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: Obx(
            () => Focus(
              focusNode: controller.focusNode.value,
              autofocus: true,
              child: MouseRegion(
                child: GestureDetector(
                  onTap: () {
                    // Request focus and show controls
                    controller.focusNode.value.requestFocus();
                    controller._cancelAndRestartTimer();
                    controller.requestFocus(context);
                  },
                  child: Obx(
                    () => AbsorbPointer(
                      absorbing: (controller.notifier?.hideStuff ?? true),
                      child: Stack(
                        children: [
                          controller.displayBufferingIndicator.value
                              ? (controller.chewieController?.bufferingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator()))
                              : _buildHitArea(context, controller),
            
                          // Info overlay
                          controller.showInfoOverlay.value
                              ? FadeTransition(
                                  opacity: controller.infoAnimation,
                                  child: '${controller.infoOverlayText.value}'.text.bold.make().pSymmetric(h: 8, v: 2).color(Colors.black).cornerRadius(90),
                                ).positioned(left: 12, top: 36)
                              : const SizedBox.shrink(),
            
                          // Bottom controls
                          Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildBottomBar(context, controller),
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
        ),
      ),
    );
  }

  // ---------------- UI helpers converted ----------------

  Widget _buildBottomBar(BuildContext context, ChiwieCustomController controller) {
    return Obx(
      () => AnimatedOpacity(
        opacity: (controller.notifier?.hideStuff ?? false) ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: controller.barHeight + (controller.chewieController?.isFullScreen ?? false ? 10.0 : 0) + 15,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: !(controller.chewieController?.isFullScreen ?? false) ? 10.0 : 0,
          ),
          child: SafeArea(
            top: false,
            bottom: controller.chewieController?.isFullScreen ?? false,
            minimum: controller.chewieController?.controlsSafeAreaMinimum ?? EdgeInsets.zero,
            child: Column(
              children: [
                '${video.title}'.text.maxLines(2).ellipsis.align(TextAlign.center).makeCentered(),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(),
                    child: Row(children: [
                      _buildProgressBar(context, controller),
                    ]),
                  ),
                ),
                Flexible(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Mute button
                      _buildMuteButton(controller.vpcontroller, controller).pOnly(right: 8),
                      _buildPosition(controller),
                      _buildSpeedButton(context, controller).pOnly(left: 8),
                      const Spacer(),
                      '${video.videoCode}'.text.extraBold.make().onInkTap(() {
                        HelperMisc.copyToClipboard(video.videoCode, showToast: true);
                      }),
                      '${video.viewCount != null && video.viewCount! > 0 ? '${video.viewCount} Views' : ''}'.text.size(9).minFontSize(9).make().pOnly(left: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildMuteButton(VideoPlayerController videoController, ChiwieCustomController controller) {
    return GestureDetector(
      onTap: () {
        controller._cancelAndRestartTimer();

        if ((controller.latestValue.value?.volume ?? 0) == 0) {
          videoController.setVolume(controller.latestVolume.value ?? 0.5);
        } else {
          controller.latestVolume.value = videoController.value.volume;
          videoController.setVolume(0.0);
        }
      },
      child: Obx(
        () => AnimatedOpacity(
          opacity: (controller.notifier?.hideStuff ?? false) ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            height: controller.barHeight,
            decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
            child: Row(
              children: [
                Icon(
                  (controller.latestValue.value?.volume ?? 0) > 0 ? CupertinoIcons.volume_up : CupertinoIcons.volume_off,
                  color: Colors.white,
                  size: 14,
                ).pOnly(right: 8),
                'Vol ${(controller.vpcontroller.value.volume * 100).toInt()}'.text.size(10).minFontSize(10).make().pOnly(top: 0),
              ],
            ).pSymmetric(h: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea(BuildContext context, ChiwieCustomController controller) {
    final bool isFinished =
        (controller.latestValue.value?.position ?? Duration.zero) >= (controller.latestValue.value?.duration ?? Duration.zero) && (controller.latestValue.value?.duration.inSeconds ?? 0) > 0;
    final bool showPlayButtonLocal = showPlayButton && !controller.dragging.value && !(controller.notifier?.hideStuff ?? false);

    return GestureDetector(
      onTap: () {
        if (controller.latestValue.value?.isPlaying ?? false) {
          if (controller.chewieController?.pauseOnBackgroundTap ?? false) {
            controller._cancelAndRestartTimer();
          } else {
            if (controller.displayTapped.value) {
              controller.notifier?.hideStuff = true;
            } else {
              controller._cancelAndRestartTimer();
            }
          }
        } else {
          controller.notifier?.hideStuff = true;
        }
      },
      child: Container(
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isFinished && !(controller.chewieController?.isLive ?? false))
              CenterSeekButton(
                iconData: Icons.replay_5,
                backgroundColor: AppColor.black120,
                iconColor: Colors.white,
                show: showPlayButtonLocal,
                fadeDuration: controller.chewieController?.materialSeekButtonFadeDuration ?? const Duration(milliseconds: 200),
                iconSize: 16,
                onPressed: () {
                  controller._seekRelative(const Duration(seconds: -5));
                },
              ).hide(),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 5.0),
              child: CenterPlayButton(
                backgroundColor: AppColor.black120,
                iconColor: Colors.white,
                isFinished: isFinished,
                isPlaying: controller.vpcontroller.value.isPlaying,
                show: showPlayButtonLocal,
                onPressed: controller._playPause,
              ),
            ).hide(),
            if (!isFinished && !(controller.chewieController?.isLive ?? false))
              CenterSeekButton(
                iconData: Icons.forward_5,
                backgroundColor: AppColor.black120,
                iconColor: Colors.white,
                show: showPlayButtonLocal,
                fadeDuration: controller.chewieController?.materialSeekButtonFadeDuration ?? const Duration(milliseconds: 200),
                iconSize: 16,
                onPressed: () {
                  controller._seekRelative(const Duration(seconds: 5));
                },
              ).hide(),
          ],
        ),
      ),
    );
  }

  Widget _buildPosition(ChiwieCustomController controller) {
    final position = controller.latestValue.value?.position ?? Duration.zero;
    final duration = controller.latestValue.value?.duration ?? Duration.zero;

    return Container(
      decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
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
      ).pSymmetric(h: 8, v: 3),
    );
  }

  Widget _buildSpeedButton(BuildContext context, ChiwieCustomController controller) {
    if ((controller.chewieController?.playbackSpeeds ?? []).isEmpty) {
      return const SizedBox();
    } else {
      return GestureDetector(
        onTap: () => controller.onSpeedButtonTap(context),
        child: Container(
          height: controller.barHeight,
          color: Colors.transparent,
          padding: const EdgeInsets.only(left: 12.0, right: 12.0),
          child: HStack(
            [
              Icon(Icons.speed, color: Colors.white, size: 16).pOnly(right: 8),
              '${(controller.latestValue.value?.playbackSpeed ?? 1.0).toDoubleStringAsFixed(digit: 2)}x'.text.size(12).make(),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildProgressBar(BuildContext context, ChiwieCustomController controller) {
    return Expanded(
      child: MaterialVideoProgressBar(
        controller.vpcontroller,
        barHeight: 3,
        height: 3,
        onDragStart: () {
          controller.onDragStartProgress();
        },
        onDragUpdate: () {
          controller.onDragUpdateProgress();
        },
        onDragEnd: () {
          controller.onDragEndProgress();
        },
        colors: controller.chewieController?.materialProgressColors ??
            ChewieProgressColors(
                playedColor: Vx.red600,
                handleColor: Theme.of(context).colorScheme.secondary,
                bufferedColor: Theme.of(context).colorScheme.surface.withValues(alpha: 1),
                backgroundColor: Theme.of(context).disabledColor.withValues(alpha: 1)),
        draggableProgressBar: controller.chewieController?.draggableProgressBar ?? true,
      ),
    );
  }
}
