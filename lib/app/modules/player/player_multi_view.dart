import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/app_color.dart';
import '../../core/app_pref.dart';
import '../../data/models/videos_entity.dart';

class PlayerMultiView extends StatefulWidget {
  const PlayerMultiView({super.key});

  @override
  State<PlayerMultiView> createState() => _PlayerMultiViewState();
}

class _PlayerMultiViewState extends State<PlayerMultiView> {
  final _items = <_MultiVideoItem>[];
  final _shortcutFocusNode = FocusNode();
  bool _isLoading = true;
  int? _focusedIndex = 0;
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _initPlayers();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initPlayers() async {
    final candidates = _extractVideos(Get.arguments);

    if (candidates.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    for (final video in candidates) {
      final path = _normalizePath(video.videoPath);
      if (path == null) {
        _items.add(
          _MultiVideoItem(
            video: video,
            errorText: 'Invalid video path',
          ),
        );
        continue;
      }

      final file = File(path);
      if (!file.existsSync()) {
        _items.add(
          _MultiVideoItem(
            video: video,
            errorText: 'File not found',
          ),
        );
        continue;
      }

      final player = Player();
      await player.setVolume(0);
      await player.setRate(AppPref.getPlayerSpeed());
      final videoController = VideoController(player);
      final item = _MultiVideoItem(
        video: video,
        player: player,
        videoController: videoController,
      );

      try {
        await player.open(
          Media(Uri.file(path).toString()),
          play: true,
        );

        item.videoSize.addListener(_onVideoSizeChanged);
        item.bindVideoSizeStream();
        _items.add(item);
      } catch (e) {
        await player.dispose();
        _items.add(
          _MultiVideoItem(
            video: video,
            errorText: 'Failed to open video: $e',
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_items.isEmpty) return;
        _focusTile(0);
      });
    }
  }

  void _focusTile(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.videoController == null) return;

    final shouldUnfocus = _focusedIndex == index;
    setState(() {
      _focusedIndex = shouldUnfocus ? null : index;
    });
    if (shouldUnfocus) {
      item.focusNode.unfocus();
      _shortcutFocusNode.requestFocus();
    } else {
      item.focusNode.requestFocus();
    }
  }

  void _toggleExpandTile(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_items[index].videoController == null) return;

    final shouldCollapse = _expandedIndex == index;
    setState(() {
      _expandedIndex = shouldCollapse ? null : index;
      _focusedIndex = index;
    });

    if (!shouldCollapse) {
      unawaited(_refreshExpandedPlayback(index));
    }

    _items[index].focusNode.requestFocus();
  }

  void _closeTile(int index) {
    if (index < 0 || index >= _items.length) return;

    final item = _items.removeAt(index);
    item.videoSize.removeListener(_onVideoSizeChanged);
    unawaited(item.dispose());

    setState(() {
      if (_items.isEmpty) {
        _focusedIndex = null;
        _expandedIndex = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Get.back();
        });
        return;
      }

      if (_expandedIndex == index) {
        _expandedIndex = null;
      } else if (_expandedIndex != null && _expandedIndex! > index) {
        _expandedIndex = _expandedIndex! - 1;
      }

      if (_focusedIndex == index) {
        _focusedIndex = math.min(index, _items.length - 1);
      } else if (_focusedIndex != null && _focusedIndex! > index) {
        _focusedIndex = _focusedIndex! - 1;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _items.isEmpty || _focusedIndex == null) return;
      _items[_focusedIndex!].focusNode.requestFocus();
    });
  }

  void _onVideoSizeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Player? get _activePlayer {
    final index = _expandedIndex ?? _focusedIndex;
    if (index == null || index < 0 || index >= _items.length) return null;
    return _items[index].player;
  }

  Future<void> _toggleActivePlayPause() async {
    final player = _activePlayer;
    if (player == null) return;

    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seekActive(Duration offset) async {
    final player = _activePlayer;
    if (player == null) return;

    final duration = player.state.duration;
    final target = player.state.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && target > duration
            ? duration
            : target;
    await player.seek(clamped);
  }

  Future<void> _changeActiveVolume(double delta) async {
    final player = _activePlayer;
    if (player == null) return;

    final target = (player.state.volume + (delta * 100)).clamp(0, 100).toDouble();
    await player.setVolume(target);
  }

  Future<void> _changeActiveSpeed(double delta) async {
    final player = _activePlayer;
    if (player == null) return;

    final target = (player.state.rate + delta).clamp(0.25, 3.0).toDouble();
    AppPref.setPlayerSpeed(target);
    await player.setRate(target);
  }

  Future<void> _toggleActiveMute() async {
    final player = _activePlayer;
    if (player == null) return;

    await player.setVolume(player.state.volume == 0 ? 100 : 0);
  }

  Future<void> _closeAllPlayers() async {
    final items = List<_MultiVideoItem>.from(_items);
    _items.clear();
    for (final item in items) {
      item.videoSize.removeListener(_onVideoSizeChanged);
      await item.dispose();
    }
    if (mounted) {
      Get.back();
    }
  }

  Future<void> _refreshExpandedPlayback(int index) async {
    if (index < 0 || index >= _items.length) return;
    final player = _items[index].player;
    if (player == null) return;

    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final position = player.state.position;
      final playing = player.state.playing;
      await player.pause();
      await player.seek(position);
      if (playing) {
        await player.play();
      }
    } catch (_) {}
  }

  List<Videos> _extractVideos(dynamic args) {
    if (args is List<Videos>) {
      return args;
    }

    if (args is Map<String, dynamic>) {
      final list = args['videos'];
      if (list is List<Videos>) {
        return list;
      }
      if (list is List) {
        return list.whereType<Videos>().toList();
      }
    }

    if (args is List) {
      return args.whereType<Videos>().toList();
    }

    return const <Videos>[];
  }

  String? _normalizePath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final value = path.trim();

    try {
      if (value.startsWith('file://')) {
        return Uri.parse(value).toFilePath();
      }
    } catch (_) {}

    return value;
  }

  ({int columns, int rows}) _resolveGrid(double width, double height, int total) {
    if (total <= 1) return (columns: 1, rows: 1);

    var columns = math.sqrt(total).ceil();
    var rows = (total / columns).ceil();

    if (width > height && columns < rows) {
      final tmp = columns;
      columns = rows;
      rows = tmp;
    }

    return (columns: columns, rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MaterialDesktopVideoControlsTheme(
          normal: const MaterialDesktopVideoControlsThemeData(
            toggleFullscreenOnDoublePress: false,
            visibleOnMount: true,
            controlsHoverDuration: Duration(hours: 24),
          ),
          fullscreen: const MaterialDesktopVideoControlsThemeData(
            toggleFullscreenOnDoublePress: false,
            visibleOnMount: true,
            controlsHoverDuration: Duration(hours: 24),
          ),
          child: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.space): const _MultiPlayPauseIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowRight): const _MultiSeekForwardShortIntent(),
              LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight): const _MultiSeekForwardMidIntent(),
              LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowRight): const _MultiSeekForwardLongIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _MultiSeekBackwardShortIntent(),
              LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft): const _MultiSeekBackwardMidIntent(),
              LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowLeft): const _MultiSeekBackwardLongIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowUp): const _MultiVolumeUpIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowDown): const _MultiVolumeDownIntent(),
              LogicalKeySet(LogicalKeyboardKey.bracketRight): const _MultiSpeedUpIntent(),
              LogicalKeySet(LogicalKeyboardKey.bracketLeft): const _MultiSpeedDownIntent(),
              LogicalKeySet(LogicalKeyboardKey.keyM): const _MultiMuteIntent(),
              LogicalKeySet(LogicalKeyboardKey.keyQ): const _MultiCloseIntent(),
            },
            child: Actions(
              actions: {
                _MultiPlayPauseIntent: CallbackAction<_MultiPlayPauseIntent>(onInvoke: (intent) { _toggleActivePlayPause(); return null; }),
                _MultiSeekForwardShortIntent: CallbackAction<_MultiSeekForwardShortIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: AppPref.getPlayerSeekShort())); return null; }),
                _MultiSeekForwardMidIntent: CallbackAction<_MultiSeekForwardMidIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: AppPref.getPlayerSeekMid())); return null; }),
                _MultiSeekForwardLongIntent: CallbackAction<_MultiSeekForwardLongIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: AppPref.getPlayerSeekLong())); return null; }),
                _MultiSeekBackwardShortIntent: CallbackAction<_MultiSeekBackwardShortIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: -AppPref.getPlayerSeekShort())); return null; }),
                _MultiSeekBackwardMidIntent: CallbackAction<_MultiSeekBackwardMidIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: -AppPref.getPlayerSeekMid())); return null; }),
                _MultiSeekBackwardLongIntent: CallbackAction<_MultiSeekBackwardLongIntent>(onInvoke: (intent) { _seekActive(Duration(seconds: -AppPref.getPlayerSeekLong())); return null; }),
                _MultiVolumeUpIntent: CallbackAction<_MultiVolumeUpIntent>(onInvoke: (intent) { _changeActiveVolume(0.05); return null; }),
                _MultiVolumeDownIntent: CallbackAction<_MultiVolumeDownIntent>(onInvoke: (intent) { _changeActiveVolume(-0.05); return null; }),
                _MultiSpeedUpIntent: CallbackAction<_MultiSpeedUpIntent>(onInvoke: (intent) { _changeActiveSpeed(0.1); return null; }),
                _MultiSpeedDownIntent: CallbackAction<_MultiSpeedDownIntent>(onInvoke: (intent) { _changeActiveSpeed(-0.1); return null; }),
                _MultiMuteIntent: CallbackAction<_MultiMuteIntent>(onInvoke: (intent) { _toggleActiveMute(); return null; }),
                _MultiCloseIntent: CallbackAction<_MultiCloseIntent>(onInvoke: (intent) { unawaited(_closeAllPlayers()); return null; }),
              },
              child: Focus(
                focusNode: _shortcutFocusNode,
                autofocus: true,
                child: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No videos provided',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final isExpandedMode = _expandedIndex != null;
    final visibleIndexes = isExpandedMode ? <int>[_expandedIndex!] : List<int>.generate(_items.length, (i) => i);

    return VStack(
      [
        HStack([
          isExpandedMode
              ? '${_items.length} Videos • Focus ${_expandedIndex! + 1}'.text.white.size(14).make().expand()
              : '${_items.length} Videos'.text.white.size(14).make().expand(),
          if (isExpandedMode)
            IconButton(
              onPressed: () => setState(() => _expandedIndex = null),
              icon: const Icon(Icons.grid_view_rounded, color: Colors.white70),
              tooltip: 'Back to Grid',
            ),
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Close',
          ),
        ]).pOnly(top: 16, left: 12, right: 12).hide(),
        LayoutBuilder(
          builder: (context, constraints) {
            return _buildTileLayout(
              constraints: constraints,
              visibleIndexes: visibleIndexes,
              isExpandedMode: isExpandedMode,
            );
          },
        ).expand(),
      ],
    );
  }

  Widget _buildTileLayout({
    required BoxConstraints constraints,
    required List<int> visibleIndexes,
    required bool isExpandedMode,
  }) {
    const spacing = 8.0;
    if (isExpandedMode || !_hasPortraitVideo(visibleIndexes)) {
      final grid = isExpandedMode ? (columns: 1, rows: 1) : _resolveGrid(constraints.maxWidth, constraints.maxHeight, visibleIndexes.length);
      final tileWidth = (constraints.maxWidth - (spacing * (grid.columns + 1))) / grid.columns;
      final tileHeight = (constraints.maxHeight - (spacing * (grid.rows + 1))) / grid.rows;
      final ratio = tileHeight <= 0 ? (16 / 9) : tileWidth / tileHeight;

      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(spacing),
        itemCount: visibleIndexes.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: grid.columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: ratio,
        ),
        itemBuilder: (context, visibleIndex) => _buildTile(visibleIndexes[visibleIndex], isExpandedMode),
      );
    }

    final portraitIndexes = visibleIndexes.where((index) => _isPortraitItem(_items[index])).toList();
    final otherIndexes = visibleIndexes.where((index) => !_isPortraitItem(_items[index])).toList();
    final otherColumns = otherIndexes.isEmpty
        ? 0
        : otherIndexes.length <= 2
            ? 1
            : math.sqrt(otherIndexes.length).ceil();
    final otherRows = otherIndexes.isEmpty ? 0 : (otherIndexes.length / otherColumns).ceil();
    final totalColumns = portraitIndexes.length + otherColumns;
    final tileWidth = (constraints.maxWidth - (spacing * (totalColumns + 1))) / totalColumns;
    final portraitHeight = constraints.maxHeight - (spacing * 2);
    final otherHeight = otherRows == 0 ? 0.0 : (constraints.maxHeight - (spacing * (otherRows + 1))) / otherRows;
    final children = <Widget>[];

    for (var i = 0; i < portraitIndexes.length; i++) {
      final index = portraitIndexes[i];
      children.add(
        Positioned(
          left: spacing + (i * (tileWidth + spacing)),
          top: spacing,
          width: tileWidth,
          height: portraitHeight,
          child: _buildTile(index, false),
        ),
      );
    }

    for (var i = 0; i < otherIndexes.length; i++) {
      final index = otherIndexes[i];
      final column = i % otherColumns;
      final row = i ~/ otherColumns;
      children.add(
        Positioned(
          left: spacing + ((portraitIndexes.length + column) * (tileWidth + spacing)),
          top: spacing + (row * (otherHeight + spacing)),
          width: tileWidth,
          height: otherHeight,
          child: _buildTile(index, false),
        ),
      );
    }

    return ClipRect(
      child: Stack(children: children),
    );
  }

  Widget _buildTile(int index, bool isExpandedMode) {
    final item = _items[index];
    return _GridTile(
      item: item,
      isFocused: _focusedIndex == index,
      isExpanded: isExpandedMode,
      onTap: () => _focusTile(index),
      onDoubleTap: () => _toggleExpandTile(index),
      onClose: () => _closeTile(index),
    );
  }

  bool _hasPortraitVideo(List<int> indexes) {
    return indexes.any((index) => _isPortraitItem(_items[index]));
  }

  bool _isPortraitItem(_MultiVideoItem item) {
    final size = item.videoSize.value;
    return size != null && size.height > size.width;
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.item,
    required this.isFocused,
    required this.isExpanded,
    required this.onTap,
    required this.onDoubleTap,
    required this.onClose,
  });

  final _MultiVideoItem item;
  final bool isFocused;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final videoController = item.videoController;
    final label = (item.video.videoCode?.trim().isNotEmpty == true)
        ? item.video.videoCode!.trim()
        : (item.video.title?.trim().isNotEmpty == true)
            ? item.video.title!.trim()
            : 'Untitled';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactTile = constraints.maxWidth < 380 || constraints.maxHeight < 240;

        return Focus(
          focusNode: item.focusNode,
          child: GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            behavior: HitTestBehavior.deferToChild,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? AppColor.border : Colors.white.withValues(alpha: 0.08),
                  width: isFocused ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: const Color(0xff121212),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: videoController == null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    item.errorText ?? 'Unknown error',
                                    style: const TextStyle(color: Colors.redAccent),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ClipRect(
                                child: ValueListenableBuilder<int?>(
                                  valueListenable: videoController.id,
                                  builder: (context, textureId, _) {
                                    if (textureId == null) {
                                      return const Center(child: CircularProgressIndicator.adaptive());
                                    }

                                    return ValueListenableBuilder<Size?>(
                                      valueListenable: item.videoSize,
                                      builder: (context, size, _) {
                                        final isPortrait = size != null && size.height > size.width;
                                        return Video(
                                          key: ValueKey('${item.video.videoPath}_${isExpanded ? 'expanded' : 'grid'}'),
                                          controller: videoController,
                                          fit: isPortrait ? BoxFit.contain : BoxFit.cover,
                                          fill: Colors.black,
                                          controls: (videoState) => const SizedBox.shrink(),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                      ),
                      Positioned(
                        left: 6,
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ).hide(),
                      if ((isFocused || isExpanded) && item.player != null)
                        Positioned(
                          left: isCompactTile ? 6 : 10,
                          right: isCompactTile ? 6 : 10,
                          bottom: isCompactTile ? 6 : 10,
                          child: _MultiPlayerControls(
                            player: item.player!,
                            isCompact: isCompactTile && !isExpanded,
                          ),
                        ),
                      if (isFocused || isExpanded)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            splashRadius: 16,
                            onPressed: onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            tooltip: 'Close Video',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MultiPlayerControls extends StatelessWidget {
  const _MultiPlayerControls({
    required this.player,
    required this.isCompact,
  });

  final Player player;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 10, vertical: isCompact ? 4 : 8),
          child: StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, positionSnap) {
              final position = positionSnap.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: player.state.duration,
                builder: (context, durationSnap) {
                  final duration = durationSnap.data ?? Duration.zero;
                  final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
                  final posMs = position.inMilliseconds.clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 1).toDouble();

                  return Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (context, playingSnap) {
                          final isPlaying = playingSnap.data ?? false;
                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            splashRadius: isCompact ? 12 : 16,
                            onPressed: () async {
                              if (isPlaying) {
                                await player.pause();
                              } else {
                                await player.play();
                              }
                            },
                            icon: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: isCompact ? 18 : 24,
                            ),
                            tooltip: isPlaying ? 'Pause' : 'Play',
                          );
                        },
                      ),
                      if (!isCompact)
                        Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: isCompact ? 2.0 : 3.0,
                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: isCompact ? 4 : 5),
                            overlayShape: RoundSliderOverlayShape(overlayRadius: isCompact ? 8 : 12),
                          ),
                          child: Slider(
                            value: posMs,
                            min: 0,
                            max: maxMs,
                            onChanged: (value) async {
                              await player.seek(Duration(milliseconds: value.round()));
                            },
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        if (!isCompact)
                          StreamBuilder<double>(
                            stream: player.stream.rate,
                            initialData: player.state.rate,
                            builder: (context, rateSnap) {
                              final rate = rateSnap.data ?? 1.0;
                              return Text(
                                '${rate.toStringAsFixed(2)}x',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ).pOnly(right: 4);
                            },
                          ),
                        StreamBuilder<double>(
                          stream: player.stream.volume,
                          initialData: player.state.volume,
                          builder: (context, volumeSnap) {
                            final volume = (volumeSnap.data ?? 0).clamp(0, 100);
                            final isMute = volume == 0;
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              splashRadius: isCompact ? 12 : 16,
                              onPressed: () async {
                                if (isMute) {
                                  await player.setVolume(100);
                                } else {
                                  await player.setVolume(0);
                                }
                              },
                              icon: Icon(
                                isMute ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white,
                                size: isCompact ? 18 : 24,
                              ),
                              tooltip: isMute ? 'Unmute' : 'Mute',
                            );
                          },
                        ),
                        if (!isCompact)
                          StreamBuilder<double>(
                            stream: player.stream.volume,
                            initialData: player.state.volume,
                            builder: (context, volumeSnap) {
                              final volume = (volumeSnap.data ?? 0).clamp(0, 100).round();
                              return Text(
                                '$volume%',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final total = value.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _MultiPlayPauseIntent extends Intent { const _MultiPlayPauseIntent(); }
class _MultiSeekForwardShortIntent extends Intent { const _MultiSeekForwardShortIntent(); }
class _MultiSeekForwardMidIntent extends Intent { const _MultiSeekForwardMidIntent(); }
class _MultiSeekForwardLongIntent extends Intent { const _MultiSeekForwardLongIntent(); }
class _MultiSeekBackwardShortIntent extends Intent { const _MultiSeekBackwardShortIntent(); }
class _MultiSeekBackwardMidIntent extends Intent { const _MultiSeekBackwardMidIntent(); }
class _MultiSeekBackwardLongIntent extends Intent { const _MultiSeekBackwardLongIntent(); }
class _MultiVolumeUpIntent extends Intent { const _MultiVolumeUpIntent(); }
class _MultiVolumeDownIntent extends Intent { const _MultiVolumeDownIntent(); }
class _MultiSpeedUpIntent extends Intent { const _MultiSpeedUpIntent(); }
class _MultiSpeedDownIntent extends Intent { const _MultiSpeedDownIntent(); }
class _MultiMuteIntent extends Intent { const _MultiMuteIntent(); }
class _MultiCloseIntent extends Intent { const _MultiCloseIntent(); }

class _MultiVideoItem {
  _MultiVideoItem({
    required this.video,
    this.player,
    this.videoController,
    this.errorText,
  });

  final Videos video;
  final Player? player;
  final VideoController? videoController;
  final String? errorText;
  final FocusNode focusNode = FocusNode();
  final ValueNotifier<Size?> videoSize = ValueNotifier<Size?>(null);
  final List<StreamSubscription> _subscriptions = [];

  void bindVideoSizeStream() {
    if (player == null) return;

    num? width;
    num? height;
    void syncSize() {
      if (width == null || height == null) return;
      if (width! <= 0 || height! <= 0) return;
      videoSize.value = Size(width!.toDouble(), height!.toDouble());
    }

    _subscriptions.add(
      player!.stream.width.listen((value) {
        width = value;
        syncSize();
      }),
    );
    _subscriptions.add(
      player!.stream.height.listen((value) {
        height = value;
        syncSize();
      }),
    );
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    try {
      await player?.dispose();
    } catch (_) {}
    videoSize.dispose();
    focusNode.dispose();
  }
}
