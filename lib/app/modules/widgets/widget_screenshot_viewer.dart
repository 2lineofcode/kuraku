import 'dart:io';
import 'dart:math' show max;

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:zoom_hover_pinch_image/zoom_hover_pinch_image.dart';

import '../../core/app_color.dart';
import '../../core/app_shortcut.dart';
import '../../data/models/videos_entity.dart';
import 'widget_media_stack.dart';
import 'widget_style.dart';
import 'widget_thumbnail.dart';

class ScreenshotViewer extends StatefulWidget {
  const ScreenshotViewer({super.key, required this.video, required this.items, required this.itemIndex,
    required this.loadVideo, required this.onClose, required this.onWarning, this.localFrames = false});

  final Videos video;
  final List<dynamic> items;
  final int itemIndex;
  final Future<Videos> Function(dynamic) loadVideo;
  final VoidCallback onClose;
  final void Function(String) onWarning;
  final bool localFrames;

  static bool hasImages(Videos video, {bool localFrames = false}) =>
      (video.screenshot?.isNotEmpty ?? false) ||
      (localFrames && (video.videoPath ?? '').isNotEmpty && File(video.videoPath!).existsSync());

  @override
  State<ScreenshotViewer> createState() => ScreenshotViewerState();
}

class ScreenshotViewerState extends State<ScreenshotViewer> {
  final _focusNode = FocusNode();
  final _thumbnails = ScrollController();
  late Videos _video = widget.video;
  late int _itemIndex = widget.itemIndex;
  int _imageIndex = 0;
  int _position = 10;
  List<int> _framePositions = List.generate(7, (index) => max(index * ExRandom.between(60, 180), 3));
  bool _loading = false;
  bool _closing = false;

  void requestFocus() => _focusNode.requestFocus();

  bool get _frames => (_video.screenshot?.isEmpty ?? true) && widget.localFrames &&
      ScreenshotViewer.hasImages(_video, localFrames: true);
  bool get _empty => !_frames && (_video.screenshot?.isEmpty ?? true);

  @override
  void dispose() {
    _focusNode.dispose();
    _thumbnails.dispose();
    super.dispose();
  }

  void _close() {
    _closing = true;
    widget.onClose();
  }

  void _followThumbnail(int index) {
    if (!_thumbnails.hasClients) return;
    final scroll = _thumbnails.position;
    final left = index * 124.0;
    final right = left + 120;
    final target = left < scroll.pixels ? left
        : right > scroll.pixels + scroll.viewportDimension ? right - scroll.viewportDimension
        : scroll.pixels;
    _thumbnails.animateTo(target.clamp(scroll.minScrollExtent, scroll.maxScrollExtent),
      duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  void _moveImage(int direction) {
    if (_empty) return;
    setState(() {
      if (_frames) {
        _position = max(0, _position + direction * 10);
      } else {
        _imageIndex = (_imageIndex + direction).clamp(0, _video.screenshot!.length - 1);
      }
    });
    if (!_frames) _followThumbnail(_imageIndex);
  }

  Future<void> _moveItem(int direction) async {
    final next = _itemIndex + direction;
    if (_loading || _closing || _itemIndex < 0 || next < 0 || next >= widget.items.length) return;
    setState(() => _loading = true);
    try {
      final video = await widget.loadVideo(widget.items[next]);
      if (!mounted || _closing) return;
      setState(() {
        _video = video;
        _itemIndex = next;
        _imageIndex = 0;
        _position = 10;
        _framePositions = List.generate(7, (index) => max(index * ExRandom.between(60, 180), 3));
      });
      if (_thumbnails.hasClients) _thumbnails.jumpTo(0);
    } catch (_) {
      if (mounted && !_closing) widget.onWarning('Failed to load screenshots');
    } finally {
      if (mounted && !_closing) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = max(Get.width * .9, 400.0);
    final height = max(Get.height * .8, 400.0) - 80;
    Widget button(dynamic icon, VoidCallback onTap) => Container(
      decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
      child: HugeIcon(icon: icon, size: AppStyle.iconSize).p12(),
    ).onInkTap(onTap);

    return FocusScope(autofocus: true, child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _moveImage(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _moveImage(1),
        const AppShortcut(LogicalKeyboardKey.arrowLeft, alt: true, includeRepeats: false): () => _moveItem(-1),
        const AppShortcut(LogicalKeyboardKey.arrowRight, alt: true, includeRepeats: false): () => _moveItem(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): _close,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(autofocus: true, focusNode: _focusNode, child: VStack([
        MediaStack([
          if (_empty && (_video.fanArt ?? '').trim().isEmpty) SizedBox(width: width, height: height) else Zoom(
            key: ValueKey(_itemIndex),
            width: width, height: height,
            child: ExThumbnail(
              imageUrl: _frames ? '' : _empty ? _video.fanArt : _video.screenshot![_imageIndex],
              videoPath: _video.videoPath,
              width: width, height: height,
              fitUrl: BoxFit.contain, fitMemory: BoxFit.contain,
              position: _frames ? _position : null,
              screenshotItems: widget.items, screenshotItemIndex: _itemIndex,
              videoCode: _video.videoCode,
            ),
          ),
          if (!_frames || (_video.videoCode ?? '').trim().isNotEmpty) Container(
            decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 12, fillColor: AppColor.black120),
            child: [
              if (!_frames) _empty ? '0/0' : '${_imageIndex + 1}/${_video.screenshot!.length}',
              if ((_video.videoCode ?? '').trim().isNotEmpty) _video.videoCode!.trim(),
            ].join(' · ').text.size(11).minFontSize(11).make().p4(),
          ).p12(),
          Align(alignment: Alignment.centerRight, child: button(HugeIcons.strokeRoundedArrowRight01, () => _moveImage(1))).positioned(right: 8, top: 0, bottom: 0),
          Align(alignment: Alignment.centerLeft, child: button(HugeIcons.strokeRoundedArrowLeft01, () => _moveImage(-1))).positioned(left: 8, top: 0, bottom: 0),
          button(HugeIcons.strokeRoundedCancel01, _close).positioned(right: 8, top: 8),
          if (_loading) const Center(child: CupertinoActivityIndicator()),
        ]),
        Container(height: 5, color: AppColor.container),
        ListView.builder(
          controller: _thumbnails,
          itemExtent: 124,
          itemCount: _frames ? 7 : (_video.screenshot?.length ?? 0),
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final position = _frames ? _framePositions[index] : 0;
            return MediaStack([
              ExThumbnail(
                imageUrl: _frames ? '' : _video.screenshot![index],
                videoPath: _video.videoPath,
                width: 120, height: 70,
                fitUrl: BoxFit.cover,
                position: _frames ? position : null,
                screenshotItems: widget.items, screenshotItemIndex: _itemIndex,
                videoCode: _video.videoCode,
              ),
              if (_frames ? _position == position : _imageIndex == index)
                Container(width: 120, height: 70, color: Colors.green.withAlpha(100)),
            ]).onInkTap(() {
              setState(() {
                if (_frames) { _position = position; } else { _imageIndex = index; }
              });
              _followThumbnail(index);
            }).pOnly(right: 4);
          },
        ).wh(double.infinity, 70),
        Container(height: 5, color: AppColor.container),
      ])),
    ));
  }
}
